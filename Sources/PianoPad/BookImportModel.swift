#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import PDFKit
import PianoAI
import UniformTypeIdentifiers
import PianoGraderCore

/// The Books tab: open a PDF, pick a piece by its systems, read it (Muse Wonder reads,
/// code measures pitch), review the bars that need a look, and save it for practice.
final class BookImportModel: ObservableObject {
    enum Phase: Equatable { case choosing, reading, review }

    enum Step: Equatable {
        case waiting, reading, measuring, done, failed(String)

        var label: String {
            switch self {
            case .waiting: return "Waiting…"
            case .reading: return "Reading with Muse Wonder…"
            case .measuring: return "Measuring pitches…"
            case .done: return "Done"
            case .failed(let why): return "Couldn't read it: \(why)"
            }
        }
    }

    /// One system of the piece being read.
    struct SystemRead: Identifiable {
        let id: Int
        let found: FoundSystem
        let gray: Gray
        let png: Data
        let image: NSImage
        var step: Step = .waiting
        var reading: SystemReading?
        var geometry: NoteheadGeometry.System?
    }

    /// One bar of the piece, as the learner reviews it.
    struct ReviewBar: Identifiable, Equatable {
        enum Resolution: Equatable { case trusted, needsReview, confirmed, fixed, nudged }

        /// Bar number in the piece, from 1.
        let id: Int
        let system: Int
        var bar: BarMerge.Bar
        var resolution: Resolution
        /// The bar cut from the page.
        let image: NSImage?

        var needsReview: Bool { resolution == .needsReview }

        /// Why it was flagged, for the review card.
        var reason: String? {
            for staff in SystemReading.StaffName.allCases {
                if case .flagged(let r) = bar.status(staff) { return r.message }
            }
            return nil
        }
    }

    @Published private(set) var documentURL: URL?
    @Published private(set) var pageCount = 0
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageImage: NSImage?
    @Published private(set) var pageSize = CGSize.zero
    @Published private(set) var systems: [FoundSystem] = []
    @Published private(set) var isLoadingPage = false
    @Published var selection: ClosedRange<Int>?
    @Published var title = ""
    @Published private(set) var phase: Phase = .choosing
    @Published private(set) var reads: [SystemRead] = []
    @Published private(set) var bars: [ReviewBar] = []
    @Published private(set) var fixing: Set<Int> = []
    /// Changes when a system's bars change, so its engraving is redrawn.
    @Published private(set) var engravingIDs: [Int: UUID] = [:]
    @Published var message: String?
    /// Says what needs a Meta key, when a feature that uses one is tried without it. Not an error:
    /// the rest of the app, and pieces already read, work without a key.
    @Published var aiKeyNote: String?
    /// The bundled books and the ones the learner opened.
    @Published private(set) var library: [LibraryBook] = []
    /// Pieces read and saved, newest first.
    @Published private(set) var pieces: [SavedPiece] = []
    /// Ask Muse Wonder again instead of using its saved readings of these lines.
    @Published var freshRead = false

    private var document: PDFDocument?
    /// Applied once the page has loaded ("Read again" on a saved piece).
    private var pendingSelection: ClosedRange<Int>?
    private var pageGray: Gray?
    private(set) weak var session: PlaySession?

    init(session: PlaySession) {
        self.session = session
        refreshLibrary()
    }

    func refreshLibrary() {
        library = BookLibrary.books()
        pieces = BookLibrary.pieces()
    }

    // MARK: Choosing

    func openBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose a music book (PDF) to read a piece from"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL, page: Int = 0) {
        guard let doc = PDFDocument(url: url) else {
            message = "Couldn't open \(url.lastPathComponent)."
            return
        }
        aiKeyNote = nil
        document = doc
        documentURL = url
        pageCount = doc.pageCount
        phase = .choosing
        if !library.contains(where: { $0.url.path == url.path }) {
            BookLibrary.remember(url)
            refreshLibrary()
        }
        show(page: page)
    }

    /// Shows a page: from the page cache when it's been seen before, otherwise rendered and
    /// scanned for lines of music (and cached). `rescan` redoes it on demand.
    func show(page index: Int, rescan: Bool = false) {
        guard let doc = document, let book = documentURL, (0..<pageCount).contains(index) else { return }
        pageIndex = index
        selection = nil
        systems = []
        isLoadingPage = true
        Task.detached(priority: .userInitiated) {
            let result: (image: Gray, systems: [FoundSystem])?
            if !rescan, let cached = BookLibrary.cachedPage(book, index) {
                result = (cached.0, cached.1)
            } else if let fresh = BookImporter.page(doc, index: index) {
                result = fresh
                BookLibrary.storePage(book, index, fresh.image, fresh.systems)
            } else {
                result = nil
            }
            await MainActor.run {
                guard self.pageIndex == index else { return }
                self.isLoadingPage = false
                guard let result else {
                    self.message = "Couldn't render page \(index + 1)."
                    return
                }
                self.pageGray = result.image
                self.pageImage = result.image.cgImage().map { NSImage(cgImage: $0, size: .zero) }
                self.pageSize = CGSize(width: result.image.width, height: result.image.height)
                self.systems = result.systems
                self.message = result.systems.isEmpty ? "No music staves found on this page." : nil
                if let pending = self.pendingSelection, pending.upperBound < result.systems.count {
                    self.selection = pending
                }
                self.pendingSelection = nil
            }
        }
    }

    /// Click: start a new selection at this system. Shift-click: extend to it.
    /// The name fills in from the page (the heading above the first line) unless the learner
    /// typed their own.
    func tapSystem(_ index: Int, extend: Bool) {
        if extend, let s = selection {
            selection = min(s.lowerBound, index)...max(s.upperBound, index)
        } else {
            selection = selection == index...index ? nil : index...index
        }
        let typed = title.trimmingCharacters(in: .whitespaces)
        guard typed.isEmpty || title == autoTitle else { return }
        autoTitle = savedForSelection?.title ?? selection.map { suggestedTitle(forLine: $0.lowerBound) } ?? ""
        title = autoTitle
    }

    /// The saved piece read from exactly these lines, if there is one: Read opens it instead
    /// of reading again (unless "Ask Muse Wonder again" is on).
    var savedForSelection: SavedPiece? {
        guard let selection, let book = documentURL?.lastPathComponent else { return nil }
        return pieces.first {
            $0.book == book && $0.page == pageIndex && $0.firstLine == selection.lowerBound && $0.lastLine == selection.upperBound
                && FileManager.default.fileExists(atPath: $0.folder.appendingPathComponent("score.json").path)
        }
    }

    /// The name filled in from the page, so typing over it is noticed.
    private var autoTitle = ""

    /// The piece's name: the largest text in the line's top margin (a heading like
    /// "Exercise No. 12"; the composer, beside it, is smaller), else "<book>, page N, line M"
    /// for a scan with no text.
    func suggestedTitle(forLine index: Int) -> String {
        let fallback = "\(documentURL?.deletingPathExtension().lastPathComponent ?? "Piece"), page \(pageIndex + 1), line \(index + 1)"
        guard systems.indices.contains(index), let page = document?.page(at: pageIndex) else { return fallback }
        let s = systems[index]
        let box = page.bounds(for: .mediaBox)
        let k = 72 / BookImporter.dpi
        // Headings sit just above the top staff, around the top of the line's crop (which reaches
        // a few spaces above the staff): look from just above the crop down to the staff, so a book
        // title higher up, and lyrics or text under the music, don't count.
        let staffTop = Double(s.top) + 3.5 * s.spacing
        let from = max(0, Double(s.top) - 0.5 * s.spacing)
        let topY = box.maxY - CGFloat(from) * k
        let height = CGFloat(staffTop - from) * k
        let rect = CGRect(x: box.minX + CGFloat(s.left) * k, y: topY - height, width: CGFloat(s.width) * k, height: height)
        guard let text = page.selection(for: rect)?.attributedString, text.length > 0 else { return fallback }
        var best: (size: CGFloat, text: String) = (0, "")
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let run = text.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !run.isEmpty else { return }
            if font.pointSize > best.size + 0.5 { best = (font.pointSize, run) }
            else if abs(font.pointSize - best.size) <= 0.5, !best.text.contains(run) { best.text += " " + run }
        }
        let name = best.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Too short to be a name (a dynamic, a bar number) or a whole paragraph: use the fallback.
        return (3...80).contains(name.count) && best.size >= 11 ? name : fallback
    }

    var canRead: Bool { selection != nil }

    // MARK: Reading

    func read() {
        if !freshRead, let saved = savedForSelection {
            practise(saved)
            return
        }
        guard let selection, let page = pageGray else { return }
        // No key is fine as long as every line has a saved reading (see `finishReading`).
        let client = try? ModelClient.configured(.meta)
        aiKeyNote = nil
        reads = selection.enumerated().compactMap { pair -> SystemRead? in
            let (k, i) = pair
            let crop = SystemFinder.crop(page, systems[i])
            guard let png = crop.pngData(), let cg = crop.cgImage() else { return nil }
            return SystemRead(id: k, found: systems[i], gray: crop, png: png, image: NSImage(cgImage: cg, size: .zero))
        }
        bars = []
        message = nil
        phase = .reading
        let jobs = reads.map { ($0.id, $0.png) }
        let fresh = freshRead
        Task {
            await withTaskGroup(of: Void.self) { group in
                for (id, png) in jobs {
                    group.addTask { await self.readSystem(id, png: png, client: client, fresh: fresh) }
                }
            }
            await MainActor.run { self.finishReading() }
        }
    }

    private func readSystem(_ id: Int, png: Data, client: ModelClient?, fresh: Bool) async {
        await setStep(id, .measuring)
        do {
            // Measure first (under a second): the bar count tells the model how many bars to read.
            let measured = try await Task.detached(priority: .userInitiated) { try NoteheadGeometry.measure(png: png) }.value
            await setStep(id, .reading)
            let reading = try await Self.cachedReading(png: png, client: client, expectedMeasures: measured.barCount,
                                                       fresh: fresh)
            await MainActor.run {
                self.reads[id].reading = reading
                self.reads[id].geometry = measured
                self.reads[id].step = .done
            }
        } catch ModelError.missingKey(_) {
            await setStep(id, .failed(Self.keyNeededReason))
        } catch {
            await setStep(id, .failed((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    private func setStep(_ id: Int, _ step: Step) async {
        await MainActor.run { self.reads[id].step = step }
    }

    private static let keyNeededReason = "it needs a Meta key"

    private func finishReading() {
        if reads.contains(where: { $0.step == .failed(Self.keyNeededReason) }) {
            reads = []
            phase = .choosing
            aiKeyNote = "Reading a new piece needs a Meta key, which you can add in AI settings. Pieces you've already read, and the rest of PerfectPiano, work without one."
            return
        }
        guard reads.allSatisfy({ $0.step == .done }) else {
            message = "Some lines couldn't be read. Check your connection and try again."
            return
        }
        var out: [ReviewBar] = []
        for r in reads {
            guard let reading = r.reading, let geometry = r.geometry else { continue }
            let merged = BarMerge.merge(reading, geometry)
            for bar in merged {
                out.append(ReviewBar(id: out.count + 1, system: r.id, bar: bar,
                                     resolution: bar.isTrusted ? .trusted : .needsReview,
                                     image: bar.pageBar.flatMap { barImage(r, $0) }))
            }
            engravingIDs[r.id] = UUID()
        }
        bars = out
        phase = .review
        // Bars the reading skipped are read again one at a time, straight away.
        let skipped = out.filter { $0.bar.upperStatus == .flagged(.skippedByReading) }.map(\.id)
        if !skipped.isEmpty {
            message = "The first reading skipped \(skipped.count) bar\(skipped.count == 1 ? "" : "s"): reading \(skipped.count == 1 ? "it" : "them") one at a time…"
            for id in skipped { fix(id) }
        }
    }

    /// The bar cut from its system image, with a little of its neighbours for context.
    private func barImage(_ r: SystemRead, _ j: Int) -> NSImage? {
        guard let g = r.geometry, j + 1 < g.barEdges.count else { return nil }
        let pad = Int(0.6 * g.upper.spacing)
        let x0 = max(0, Int(g.barEdges[j]) - pad), x1 = min(r.gray.width, Int(g.barEdges[j + 1]) + pad)
        guard x1 > x0 else { return nil }
        let found = FoundSystem(index: 0, left: x0, top: 0, right: x1, bottom: r.gray.height, spacing: g.upper.spacing)
        return SystemFinder.crop(r.gray, found).cgImage().map { NSImage(cgImage: $0, size: .zero) }
    }

    /// Readings are cached by image, so reading the same piece again is instant (and free).
    static func cachedReading(png: Data, client: ModelClient?, reader: SystemReader? = nil, expectedMeasures: Int? = nil,
                              fresh: Bool = false) async throws -> SystemReading {
        let url = cacheURL(png: png, expectedMeasures: expectedMeasures)
        let activeReader = reader ?? client.map { SystemReader(client: $0) }
        // Without a key a saved reading is still used, even when asked to read again.
        if !fresh || activeReader == nil, let data = try? Data(contentsOf: url),
           let cached = try? JSONDecoder().decode(SystemReading.self, from: data) {
            return cached
        }
        guard let activeReader else { throw ModelError.missingKey(.meta) }
        let reading = try await activeReader.read(png: png, expectedMeasures: expectedMeasures)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(reading).write(to: url)
        return reading
    }

    /// The key covers the image and how it was asked (v2: with the measured bar count).
    static func cacheURL(png: Data, expectedMeasures: Int?) -> URL {
        let key = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + "-v2-\(expectedMeasures ?? 0)"
        return cacheFolder.appendingPathComponent("\(key).json")
    }

    static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PianoPad/ReadingCache")
    }

    // MARK: Review

    var toReview: Int { bars.filter(\.needsReview).count }
    var canSave: Bool { phase == .review && !bars.isEmpty && toReview == 0 }

    func bars(inSystem s: Int) -> [ReviewBar] { bars.filter { $0.system == s } }

    /// The engraving of one system's bars, with the bars still to check tinted.
    func engraving(ofSystem s: Int) -> (score: Score, flagged: Set<Int>)? {
        let mine = bars(inSystem: s)
        guard !mine.isEmpty else { return nil }
        let piece = ScoreWriter.write(mine.map(\.bar), title: "")
        let flagged = Set(mine.enumerated().filter { $0.element.needsReview }.map { $0.offset + 1 })
        return (piece.score, flagged)
    }

    func confirm(_ id: Int) {
        update(id) { $0.resolution = .confirmed }
    }

    /// Moves one note up or down a line or space, and plays it.
    func nudge(_ id: Int, staff: SystemReading.StaffName, note k: Int, by delta: Int) {
        update(id) { b in
            var notes = staff == .upper ? b.bar.upper : b.bar.lower
            guard notes.indices.contains(k), !notes[k].note.rest else { return }
            notes[k].note.position += delta
            if staff == .upper { b.bar.upper = notes } else { b.bar.lower = notes }
            b.resolution = .nudged
            session?.previewPitch(StaffPitch.midi(clef: notes[k].clef, position: notes[k].note.position,
                                                  accidental: notes[k].note.accidental))
        }
    }

    /// Plays one bar, both hands, at a steady 80 bpm.
    func listen(_ id: Int) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        var notes: [(pitch: Int, start: Double, length: Double)] = []
        for staff in SystemReading.StaffName.allCases {
            var t = 0.0
            for n in b.bar.notes(staff) {
                let seconds = n.note.quarters * 60 / 80
                if !n.note.rest {
                    notes.append((StaffPitch.midi(clef: n.clef, position: n.note.position, accidental: n.note.accidental),
                                  t, seconds * 0.9))
                }
                t += seconds
            }
        }
        session?.previewNotes(notes)
    }

    /// Asks Muse Wonder to read just this bar again (zoomed in), then measures and merges it.
    func fix(_ id: Int) {
        guard let b = bars.first(where: { $0.id == id }), let r = reads.first(where: { $0.id == b.system }),
              let g = r.geometry else { return }
        guard let j = b.bar.pageBar, j + 1 < g.barEdges.count else {
            message = "Bar \(id) couldn't be found on the page, so it can't be read again. Nudge its notes or tap That's right."
            return
        }
        guard let client = try? ModelClient.configured(.meta) else {
            aiKeyNote = "Reading a bar again needs a Meta key, which you can add in AI settings. You can still nudge its notes or tap That's right."
            if message?.hasPrefix("The first reading skipped") == true { message = nil }
            return
        }
        aiKeyNote = nil
        // The bar alone, with its clefs' context lost: zoom by cropping just this bar.
        let pad = Int(0.6 * g.upper.spacing)
        let x0 = max(0, Int(g.barEdges[j]) - pad)
        let x1 = min(r.gray.width, Int(g.barEdges[j + 1]) + pad)
        let crop = SystemFinder.crop(r.gray, FoundSystem(index: 0, left: x0, top: 0, right: x1, bottom: r.gray.height,
                                                         spacing: g.upper.spacing))
        guard let png = crop.pngData() else { return }
        fixing.insert(id)
        Task {
            do {
                let reading = try await SystemReader(client: client, reasoningEffort: "high").read(png: png, expectedMeasures: 1)
                // Use the measure with the most notes (a crop can catch a sliver of a neighbour).
                guard let measure = reading.measures.max(by: {
                    $0.upper.notes.count + $0.lower.notes.count < $1.upper.notes.count + $1.lower.notes.count
                }) else { throw ModelError.badResponse("no bar in the reply") }
                var oneBar = g
                oneBar.barEdges = [g.barEdges[j], g.barEdges[j + 1]]
                var reread = BarMerge.merge(SystemReading(measureCount: 1, measures: [measure]), oneBar)[0]
                reread.pageBar = j
                let merged = reread
                await MainActor.run {
                    self.fixing.remove(id)
                    if self.fixing.isEmpty, self.message?.hasPrefix("The first reading skipped") == true { self.message = nil }
                    self.update(id) { rb in
                        rb.bar = merged
                        rb.resolution = merged.isTrusted ? .fixed : .needsReview
                    }
                    if self.bars.first(where: { $0.id == id })?.needsReview == true {
                        self.message = "Bar \(id) still needs a look: nudge any wrong note, then tap That's right."
                    }
                }
            } catch {
                await MainActor.run {
                    self.fixing.remove(id)
                    self.message = "Couldn't re-read bar \(id): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
                }
            }
        }
    }

    private func update(_ id: Int, _ change: (inout ReviewBar) -> Void) {
        guard let i = bars.firstIndex(where: { $0.id == id }) else { return }
        change(&bars[i])
        engravingIDs[bars[i].system] = UUID()
    }

    func startOver() {
        aiKeyNote = nil
        phase = .choosing
        reads = []
        bars = []
    }

    // MARK: Saving

    /// Writes the piece (MIDI, MusicXML, score) and opens it in Practice.
    func save() {
        guard canSave else { return }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? (reads.first.map { suggestedTitle(forLine: $0.found.index) } ?? "Piece")
            : title.trimmingCharacters(in: .whitespaces)
        let piece = ScoreWriter.write(bars.map(\.bar), title: name)
        let saved = SavedPiece(id: Self.slug(name), title: name, book: documentURL?.lastPathComponent ?? "",
                               page: pageIndex, firstLine: reads.first?.found.index ?? 0,
                               lastLine: reads.last?.found.index ?? 0, created: Date())
        let folder = saved.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try piece.midi.write(to: folder.appendingPathComponent("piece.mid"))
            try Data(piece.musicXML.utf8).write(to: folder.appendingPathComponent("piece.musicxml"))
            try JSONEncoder().encode(piece.score).write(to: folder.appendingPathComponent("score.json"))
            try BookLibrary.store(saved)
            message = nil
            refreshLibrary()
            practise(saved)
        } catch {
            message = "Couldn't save the piece: \(error.localizedDescription)"
        }
    }

    // MARK: Saved pieces

    /// Opens a saved piece in Practice, as it was read and checked: no reading again.
    func practise(_ piece: SavedPiece) {
        do {
            let score = try JSONDecoder().decode(Score.self, from: Data(contentsOf: piece.folder.appendingPathComponent("score.json")))
            session?.tab = .practice
            session?.loadReference(piece.folder.appendingPathComponent("piece.mid"), remember: false, writtenScore: score)
        } catch {
            message = "Couldn't open \(piece.title): \(error.localizedDescription)"
        }
    }

    /// Goes back to the piece's page with its lines selected, ready to read again.
    func readAgain(_ piece: SavedPiece) {
        guard let book = library.first(where: { $0.url.lastPathComponent == piece.book }) else {
            message = "Open \(piece.book) first: it isn't in your books."
            return
        }
        title = piece.title
        pendingSelection = piece.firstLine...piece.lastLine
        open(book.url, page: piece.page)
    }

    func showInFinder(_ piece: SavedPiece) {
        NSWorkspace.shared.activateFileViewerSelecting([piece.folder])
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- "))
        let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "Piece" : cleaned
    }
}
#endif
