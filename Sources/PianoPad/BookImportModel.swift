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
        let indexInSystem: Int
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

    private var document: PDFDocument?
    private var pageGray: Gray?
    private weak var session: PlaySession?

    init(session: PlaySession) {
        self.session = session
    }

    // MARK: Choosing

    func openBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose a music book (PDF) to read a piece from"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard let doc = PDFDocument(url: url) else {
            message = "Couldn't open \(url.lastPathComponent)."
            return
        }
        document = doc
        documentURL = url
        pageCount = doc.pageCount
        phase = .choosing
        show(page: 0)
    }

    func show(page index: Int) {
        guard let doc = document, (0..<pageCount).contains(index) else { return }
        pageIndex = index
        selection = nil
        systems = []
        isLoadingPage = true
        Task.detached(priority: .userInitiated) {
            let result = BookImporter.page(doc, index: index)
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
            }
        }
    }

    /// Click: start a new selection at this system. Shift-click: extend to it.
    func tapSystem(_ index: Int, extend: Bool) {
        if extend, let s = selection {
            selection = min(s.lowerBound, index)...max(s.upperBound, index)
        } else {
            selection = selection == index...index ? nil : index...index
        }
    }

    var canRead: Bool { selection != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Reading

    func read() {
        guard let selection, let page = pageGray else { return }
        let client: ModelClient
        do {
            client = try ModelClient.configured(.meta)
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
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
        Task {
            await withTaskGroup(of: Void.self) { group in
                for (id, png) in jobs {
                    group.addTask { await self.readSystem(id, png: png, client: client) }
                }
            }
            await MainActor.run { self.finishReading() }
        }
    }

    private func readSystem(_ id: Int, png: Data, client: ModelClient) async {
        await setStep(id, .reading)
        do {
            async let geometry = Task.detached(priority: .userInitiated) { try NoteheadGeometry.measure(png: png) }.value
            let reading = try await Self.cachedReading(png: png, client: client)
            await setStep(id, .measuring)
            let measured = try await geometry
            await MainActor.run {
                self.reads[id].reading = reading
                self.reads[id].geometry = measured
                self.reads[id].step = .done
            }
        } catch {
            await setStep(id, .failed((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    private func setStep(_ id: Int, _ step: Step) async {
        await MainActor.run { self.reads[id].step = step }
    }

    private func finishReading() {
        guard reads.allSatisfy({ $0.step == .done }) else {
            message = "Some lines couldn't be read. Check your connection and try again."
            return
        }
        var out: [ReviewBar] = []
        for r in reads {
            guard let reading = r.reading, let geometry = r.geometry else { continue }
            let merged = BarMerge.merge(reading, geometry)
            for (j, bar) in merged.enumerated() {
                let trusted = bar.upperStatus.isTrusted && bar.lowerStatus.isTrusted
                out.append(ReviewBar(id: out.count + 1, system: r.id, indexInSystem: j, bar: bar,
                                     resolution: trusted ? .trusted : .needsReview,
                                     image: barImage(r, j)))
            }
            engravingIDs[r.id] = UUID()
        }
        bars = out
        phase = .review
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
    static func cachedReading(png: Data, client: ModelClient, reader: SystemReader? = nil) async throws -> SystemReading {
        let key = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let url = cacheFolder.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(SystemReading.self, from: data) {
            return cached
        }
        let reading = try await (reader ?? SystemReader(client: client)).read(png: png)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(reading).write(to: url)
        return reading
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
              let g = r.geometry, b.indexInSystem + 1 < g.barEdges.count else { return }
        let client: ModelClient
        do { client = try ModelClient.configured(.meta) } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        // The bar alone, with its clefs' context lost: zoom by cropping just this bar.
        let pad = Int(0.6 * g.upper.spacing)
        let x0 = max(0, Int(g.barEdges[b.indexInSystem]) - pad)
        let x1 = min(r.gray.width, Int(g.barEdges[b.indexInSystem + 1]) + pad)
        let crop = SystemFinder.crop(r.gray, FoundSystem(index: 0, left: x0, top: 0, right: x1, bottom: r.gray.height,
                                                         spacing: g.upper.spacing))
        guard let png = crop.pngData() else { return }
        fixing.insert(id)
        Task {
            do {
                let reading = try await SystemReader(client: client, reasoningEffort: "high").read(png: png)
                // Use the measure with the most notes (a crop can catch a sliver of a neighbour).
                guard let measure = reading.measures.max(by: {
                    $0.upper.notes.count + $0.lower.notes.count < $1.upper.notes.count + $1.lower.notes.count
                }) else { throw ModelError.badResponse("no bar in the reply") }
                var oneBar = g
                oneBar.barEdges = [g.barEdges[b.indexInSystem], g.barEdges[b.indexInSystem + 1]]
                let merged = BarMerge.merge(SystemReading(measureCount: 1, measures: [measure]), oneBar)[0]
                await MainActor.run {
                    self.fixing.remove(id)
                    self.update(id) { rb in
                        rb.bar = merged
                        rb.resolution = merged.upperStatus.isTrusted && merged.lowerStatus.isTrusted ? .fixed : .needsReview
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
        phase = .choosing
        reads = []
        bars = []
    }

    // MARK: Saving

    /// Writes the piece (MIDI, MusicXML, score) and opens it in Practice.
    func save() {
        guard canSave else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let piece = ScoreWriter.write(bars.map(\.bar), title: name)
        let folder = Self.importedFolder.appendingPathComponent(Self.slug(name))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let midiURL = folder.appendingPathComponent("piece.mid")
            try piece.midi.write(to: midiURL)
            try Data(piece.musicXML.utf8).write(to: folder.appendingPathComponent("piece.musicxml"))
            try JSONEncoder().encode(piece.score).write(to: folder.appendingPathComponent("score.json"))
            message = nil
            session?.tab = .practice
            session?.loadReference(midiURL, remember: false, writtenScore: piece.score)
        } catch {
            message = "Couldn't save the piece: \(error.localizedDescription)"
        }
    }

    static var importedFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PianoPad/Imported")
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- "))
        let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "Piece" : cleaned
    }
}
#endif
