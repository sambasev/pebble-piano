#if os(macOS)
import Foundation
import PianoCatalog
import SwiftUI

@MainActor
final class MusicLibraryModel: ObservableObject {
    let catalog: MusicCatalog?
    let cache: CatalogCache
    @Published var query = ""
    @Published var composer: String?
    @Published var difficulty: CatalogPiece.Difficulty?
    @Published var downloadedOnly = false
    @Published var selectedID: String?
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private var requestID: UUID?
    private var task: Task<Void, Never>?

    init(catalog: MusicCatalog? = nil, cache: CatalogCache = CatalogCache()) {
        self.cache = cache
        do { self.catalog = try catalog ?? MusicCatalog.bundled() }
        catch { self.catalog = nil; self.error = error.localizedDescription }
    }

    var pieces: [CatalogPiece] { catalog?.pieces ?? [] }
    var composers: [String] { Set(pieces.map(\.composer)).sorted() }
    var filtered: [CatalogPiece] {
        pieces.filter {
            $0.matches(query: query, composer: composer, difficulty: difficulty)
                && (!downloadedOnly || downloaded.contains($0.id))
        }
    }
    var selected: CatalogPiece? { filtered.first { $0.id == selectedID } ?? filtered.first }

    func refreshDownloads() async {
        downloaded = await cache.downloadedIDs(in: pieces)
    }

    func cancel() {
        requestID = nil
        task?.cancel(); task = nil
        downloadingID = nil; progress = nil
    }

    func open(_ piece: CatalogPiece, onOpen: @escaping (URL) -> Bool) {
        cancel()
        error = nil
        let token = UUID()
        requestID = token; downloadingID = piece.id
        task = Task { [weak self, cache] in
            do {
                let url = try await cache.prepare(piece) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.requestID == token else { return }
                        self.progress = value
                    }
                }
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }
                self.downloaded.insert(piece.id)
                self.requestID = nil; self.downloadingID = nil; self.task = nil
                if !onOpen(url) { self.error = "Couldn't open this piece. Please try again." }
            } catch {
                guard let self, self.requestID == token else { return }
                self.requestID = nil; self.downloadingID = nil; self.task = nil
                if !(error is CancellationError) { self.error = "\(error.localizedDescription) Select a piece and try again." }
            }
        }
    }
}
#endif
