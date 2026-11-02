#if os(macOS)
import Foundation
import PianoAI

/// A PDF music book the Books tab can open.
struct LibraryBook: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    /// Shipped with the app (Books/), as opposed to one the learner opened.
    let bundled: Bool
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// A piece read from a book and saved: what it came from, so it can be read again on demand.
struct SavedPiece: Codable, Identifiable, Hashable {
    /// The folder name under Imported/.
    var id: String
    var title: String
    /// The book's file name.
    var book: String
    /// Page, from 0.
    var page: Int
    /// The lines (systems) on that page, from 0.
    var firstLine: Int
    var lastLine: Int
    var created: Date

    var folder: URL { BookLibrary.importedFolder.appendingPathComponent(id) }
}

/// The books and saved pieces, and what's been worked out about each book's pages.
///
/// Three caches, each filled the first time it's needed and redone only on demand:
/// - a page's rendering and the lines of music found on it (BookCache/<book>/page-N.*):
///   "Re-scan page" redoes it;
/// - each line's reading by Muse Wonder, by image (ReadingCache/): "Ask Muse Wonder again"
///   skips it;
/// - saved pieces (Imported/<piece>/): open straight into Practice; "Read again" redoes them.
enum BookLibrary {
    /// Tests point this at a temporary folder.
    static var supportOverride: URL?
    static var support: URL {
        supportOverride ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("PianoPad")
    }

    static var importedFolder: URL { support.appendingPathComponent("Imported") }

    // MARK: Books

    /// The bundled books (Books/*.pdf), then the ones the learner opened, most recent first.
    static func books() -> [LibraryBook] {
        var out: [LibraryBook] = []
        if let folder = PlaySession.bundledResource("Books"),
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            out += files.filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { LibraryBook(url: $0, bundled: true) }
        }
        let bundledNames = Set(out.map { $0.url.lastPathComponent })
        out += rememberedURLs().filter { !bundledNames.contains($0.lastPathComponent) }.map { LibraryBook(url: $0, bundled: false) }
        return out
    }

    private static let recentKey = "books.recent"

    /// Remembers a book the learner opened (a security-scoped bookmark, for the sandboxed app).
    static func remember(_ url: URL) {
        // Security-scoped for the sandboxed app; a plain bookmark when that isn't available.
        guard let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                    relativeTo: nil))
                ?? (try? url.bookmarkData()) else { return }
        var list = UserDefaults.standard.array(forKey: recentKey) as? [Data] ?? []
        list.removeAll { resolve($0)?.path == url.path }
        list.insert(bookmark, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: recentKey)
    }

    static func rememberedURLs() -> [URL] {
        (UserDefaults.standard.array(forKey: recentKey) as? [Data] ?? []).compactMap(resolve)
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        let url = (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                            bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: bookmark, relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Page cache

    /// Bumped when finding the lines of music changes, so pages are scanned again.
    /// 2: paragraphs of text are no longer taken for staves.
    static let pageScanVersion = 2

    /// One folder per book version: its name, size and modification date.
    static func cacheFolder(for book: URL) -> URL {
        let values = try? book.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let stamp = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let name = book.deletingPathExtension().lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return support.appendingPathComponent("BookCache/\(name)-\(size)-\(stamp)-v\(pageScanVersion)")
    }

    struct CachedPage: Codable {
        var systems: [FoundSystem]
    }

    static func cachedPage(_ book: URL, _ index: Int) -> (Gray, [FoundSystem])? {
        let folder = cacheFolder(for: book)
        guard let png = try? Data(contentsOf: folder.appendingPathComponent("page-\(index).png")),
              let json = try? Data(contentsOf: folder.appendingPathComponent("page-\(index).json")),
              let gray = Gray.decode(png),
              let page = try? JSONDecoder().decode(CachedPage.self, from: json)
        else { return nil }
        return (gray, page.systems)
    }

    /// Deletes the book's other cache folders: left by an earlier copy of the book (a different
    /// size or date) or an earlier `pageScanVersion`. Nothing reads them again.
    static func pruneCaches(for book: URL) {
        let current = cacheFolder(for: book)
        let parent = current.deletingLastPathComponent()
        let name = book.deletingPathExtension().lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for folder in folders where folder != current.lastPathComponent && folder.hasPrefix(name + "-") {
            // Only <name>-<size>-<date>[-v<n>], so "book" doesn't take "book-2"'s folders.
            let rest = folder.dropFirst(name.count + 1).split(separator: "-", omittingEmptySubsequences: false)
            let isOurs = (rest.count == 2 || (rest.count == 3 && rest[2].hasPrefix("v")))
                && rest.prefix(2).allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
            if isOurs { try? FileManager.default.removeItem(at: parent.appendingPathComponent(folder)) }
        }
    }

    /// Just the lines found on a page, without decoding its image: for skimming many pages.
    static func cachedSystems(_ book: URL, _ index: Int) -> [FoundSystem]? {
        guard let json = try? Data(contentsOf: cacheFolder(for: book).appendingPathComponent("page-\(index).json")) else { return nil }
        return (try? JSONDecoder().decode(CachedPage.self, from: json))?.systems
    }

    static func storePage(_ book: URL, _ index: Int, _ gray: Gray, _ systems: [FoundSystem]) {
        let folder = cacheFolder(for: book)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let png = gray.pngData() { try? png.write(to: folder.appendingPathComponent("page-\(index).png")) }
        if let json = try? JSONEncoder().encode(CachedPage(systems: systems)) {
            try? json.write(to: folder.appendingPathComponent("page-\(index).json"))
        }
    }

    /// Rewrites just the lines found on a page (one resized by hand), keeping its image.
    static func storeSystems(_ book: URL, _ index: Int, _ systems: [FoundSystem]) {
        let folder = cacheFolder(for: book)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let json = try? JSONEncoder().encode(CachedPage(systems: systems)) {
            try? json.write(to: folder.appendingPathComponent("page-\(index).json"))
        }
    }

    // MARK: Saved pieces

    static func pieces() -> [SavedPiece] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: importedFolder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("piece.json")) else { return nil }
            return try? decoder.decode(SavedPiece.self, from: data)
        }
        .sorted { $0.created > $1.created }
    }

    static func store(_ piece: SavedPiece) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(piece).write(to: piece.folder.appendingPathComponent("piece.json"))
    }
}
#endif
