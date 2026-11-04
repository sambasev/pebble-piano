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
///
/// Reading and re-reading a bar run in the background. Each belongs to one read (`readID`):
/// Cancel, Start over, a new read or opening a book cancels them, and anything they finish
/// afterwards is dropped, so it can't land in an emptied list or in the next piece.
final class BookImportModel: ObservableObject {
    enum Phase: Equatable { case choosing, reading, review }

    /// How a line's two staves are played.
    enum Layout: Equatable {
        /// Upper staff right hand, lower staff left hand, at the same time (a grand staff).
        case together
        /// Each staff is a line of its own, played one after the other, top staff first.
        case separate
    }

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

    /// The lines of a book page a piece is read from.
    struct PieceSource: Equatable {
        /// The book's file name.
        var book: String
        /// From 0.
        var page: Int
        /// The lines (systems) on the page, from 0.
        var lines: ClosedRange<Int>
    }

    /// One system of the piece being read.
    struct SystemRead: Identifiable {
        let id: Int
        let found: FoundSystem
        let gray: Gray
        let png: Data
        let image: NSImage
        /// One staff of a line on its own (staves read separately), not a pair.
        var singleStaff = false
        /// The clefs the music is read in (the learner's choice, else what's printed).
        var upperClef: SystemReading.Clef = .treble
        var lowerClef: SystemReading.Clef = .treble
        var step: Step = .waiting
        var reading: SystemReading?
        var geometry: NoteheadGeometry.System?
    }

    /// A note in a bar: which staff, and which of its notes (from 0).
    struct NoteRef: Equatable {
        var staff: SystemReading.StaffName
        var index: Int
    }

    /// The review at one moment, for Undo.
    struct ReviewSnapshot {
        var bars: [ReviewBar]
        var selectedBar: Int?
        var selectedNote: NoteRef?
    }

    /// One bar of the piece, as the learner reviews it.
    struct ReviewBar: Identifiable, Equatable {
        typealias Resolution = PieceCorrection.Resolution

        /// Bar number in the piece, from 1.
        let id: Int
        let system: Int
        var bar: BarMerge.Bar
        /// As the first reading had it.
        let original: BarMerge.Bar
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
    /// Lines on this page whose box was resized by hand since it was shown: a piece saved from
    /// the old box isn't reopened for them, they're read again.
    @Published private(set) var resizedLines: Set<Int> = []
    @Published private(set) var isLoadingPage = false
    /// The page being looked at while skipping to the next page with music on it.
    @Published private(set) var seekingPage: Int?
    private var seekTask: Task<Void, Never>?
    @Published var selection: ClosedRange<Int>?
    @Published var title = ""
    @Published private(set) var phase: Phase = .choosing
    /// What's being read or checked: saving writes the piece for these lines.
    @Published private(set) var source: PieceSource?
    @Published private(set) var reads: [SystemRead] = []
    @Published private(set) var bars: [ReviewBar] = []
    @Published private(set) var fixing: Set<Int> = []
    /// The bar being looked at in the review (its card is open), and the note picked in it.
    @Published private(set) var selectedBar: Int?
    @Published private(set) var selectedNote: NoteRef?
    /// The last read failed (not for want of a key): Try again reads the same lines, reusing the
    /// lines that were read (they're saved), so only the failed ones are asked again.
    @Published private(set) var canRetryRead = false
    /// Bars read again after the learner had corrected or checked them: what the new reading
    /// says, waiting for Use this or Keep mine. A correction is never replaced unasked.
    @Published private(set) var proposals: [Int: BarMerge.Bar] = [:]
    /// The review as it was before each change, newest last (Undo), and changes undone (Redo).
    @Published private(set) var undoStack: [ReviewSnapshot] = []
    @Published private(set) var redoStack: [ReviewSnapshot] = []
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
    /// How the selected lines' staves are read, and in which clefs: filled in from the clefs
    /// printed on the page, and changed by the learner (`choose…`).
    @Published private(set) var layout: Layout = .together
    @Published private(set) var upperClef: SystemReading.Clef = .treble
    @Published private(set) var lowerClef: SystemReading.Clef = .treble
    /// The page doesn't print a treble clef over a bass clef on every selected line, so the
    /// setup is a guess the learner should check.
    @Published private(set) var setupUnclear = false
    /// The learner changed the setup: it isn't replaced from the page, and a piece saved from
    /// these lines (perhaps read another way) isn't reopened.
    @Published private(set) var setupEdited = false
    /// Looking at the selected lines' printed clefs; Read waits for it.
    @Published private(set) var checkingClefs = false
    private var readWhenChecked = false

    private var document: PDFDocument?
    /// Small pictures of the open book's pages, for the page strip; made as they scroll into view.
    private let thumbnails = NSCache<NSNumber, NSImage>()
    /// Applied once the page has loaded ("Read again" on a saved piece).
    private var pendingSelection: ClosedRange<Int>?
    /// Read once the page has loaded ("Check and correct" on a piece saved before checks were kept).
    private var pendingCorrection: (lines: ClosedRange<Int>, layout: Layout, upper: SystemReading.Clef, lower: SystemReading.Clef)?
    /// Shown when the reading under way reaches the review.
    private var afterReadingNote: String?
    /// The next read uses saved readings only, never Muse Wonder (checking a piece saved before
    /// checks were kept: it's meant to be free, and to be the reading the piece was saved from).
    private var savedReadingsOnly = false
    private var pageGray: Gray?
    private(set) weak var session: PlaySession?

    /// Changes with every read and Start over; work started for an earlier read is dropped.
    private var readID = UUID()
    /// The read under way (tests wait on it).
    private(set) var readTask: Task<Void, Never>?
    /// Bars being read again, by bar number (tests wait on them).
    private(set) var fixTasks: [Int: Task<Void, Never>] = [:]

    // What reading uses, replaced in tests.
    /// Measures one line's noteheads and bar lines: (image, one staff on its own) → bars.
    var measureLine: @Sendable (Data, Bool) throws -> NoteheadGeometry.System = {
        try NoteheadGeometry.measure(png: $0, singleStaff: $1)
    }
    /// How a line is read: its saved reading if there is one (else Muse Wonder), Muse Wonder
    /// again, or only a saved reading (never Muse Wonder: `ModelError.missingKey` if there's none).
    enum ReadingSource: Sendable { case saved, fresh, savedOnly }

    /// Reads one line: (image, bars measured, one staff on its own, how) → reading.
    /// Saved readings are used without a key.
    var readLine: @Sendable (Data, Int, Bool, ReadingSource) async throws -> SystemReading = { png, measures, single, how in
        try await BookImportModel.cachedReading(png: png, client: how == .savedOnly ? nil : try? ModelClient.configured(.meta),
                                                expectedMeasures: measures, singleStaff: single, fresh: how == .fresh)
    }
    /// Reads one bar again, zoomed in: (image, one staff on its own, ask again) → reading.
    /// Saved by image like a line's reading, so reading the piece again re-reads its skipped
    /// bars for free; `ModelError.missingKey` when there's neither a key nor a saved reading.
    var barReader: @Sendable (Data, Bool, Bool) async throws -> SystemReading = { png, single, fresh in
        let client = try? ModelClient.configured(.meta)
        return try await BookImportModel.cachedReading(png: png, client: client,
                                                       reader: client.map { SystemReader(client: $0, reasoningEffort: "high") },
                                                       expectedMeasures: 1, singleStaff: single, fresh: fresh)
    }

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
        if phase == .reading { startOver() } else { cancelReading() }
        document = doc
        thumbnails.removeAllObjects()
        documentURL = url
        pageCount = doc.pageCount
        phase = .choosing
        if !library.contains(where: { $0.url.path == url.path }) {
            BookLibrary.remember(url)
            refreshLibrary()
        }
        Task.detached(priority: .utility) { BookLibrary.pruneCaches(for: url) }
        show(page: page)
    }

    /// A small picture of page `index` of the open book, for the page strip.
    func thumbnail(ofPage index: Int) -> NSImage? {
        if let cached = thumbnails.object(forKey: index as NSNumber) { return cached }
        guard let page = document?.page(at: index) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
        thumbnails.setObject(image, forKey: index as NSNumber)
        return image
    }

    /// Shows a page: from the page cache when it's been seen before, otherwise rendered and
    /// scanned for lines of music (and cached). `rescan` redoes it on demand.
    func show(page index: Int, rescan: Bool = false) {
        guard let doc = document, let book = documentURL, (0..<pageCount).contains(index), phase != .reading else { return }
        seekTask?.cancel()
        seekingPage = nil
        pageIndex = index
        selection = nil
        canRetryRead = false
        resetSetup()
        systems = []
        resizedLines = []
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
                    self.checkClefs()
                }
                self.pendingSelection = nil
                if let pending = self.pendingCorrection {
                    self.pendingCorrection = nil
                    guard pending.lines.upperBound < result.systems.count else {
                        self.afterReadingNote = nil
                        self.message = "The lines of this piece aren't on page \(index + 1) any more (was the page re-scanned?)."
                        return
                    }
                    self.selection = pending.lines
                    self.layout = pending.layout
                    self.upperClef = pending.upper
                    self.lowerClef = pending.lower
                    self.setupEdited = true
                    self.savedReadingsOnly = true
                    self.readSelection()
                }
            }
        }
    }

    /// Pages scanned at once while skipping to music: one per performance core, at most 8 (each
    /// page being scanned holds a few tens of MB). Not the efficiency cores: a batch waits for
    /// its slowest page. An M1 has 4.
    static let seekLanes: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) != 0 || cores < 1 {
            cores = Int32(ProcessInfo.processInfo.activeProcessorCount)
        }
        return min(8, max(1, Int(cores)))
    }()

    /// Skips to the nearest page before (`step` -1) or after (+1) this one with music found on
    /// it. Pages not seen before are scanned (and cached) on the way, `seekLanes` at a time, so
    /// the first skip over a long stretch of text can take a moment; `seekingPage` says where
    /// it has got to.
    func showMusic(step: Int) {
        guard let book = documentURL, phase != .reading else { return }
        seekTask?.cancel()
        let start = pageIndex, count = pageCount
        seekingPage = start + step
        seekTask = Task.detached(priority: .userInitiated) {
            // PDFKit isn't safe to draw from on several threads at once: each lane has its own copy.
            let docs = (0..<Self.seekLanes).compactMap { _ in PDFDocument(url: book) }
            var found: Int?
            var next = start + step
            while found == nil, (0..<count).contains(next), !docs.isEmpty {
                if Task.isCancelled { return }
                let batch = (0..<docs.count).map { next + $0 * step }.filter { (0..<count).contains($0) }
                let furthest = batch.last!
                await MainActor.run { self.seekingPage = furthest }
                let withMusic = await withTaskGroup(of: Int?.self) { group in
                    for (lane, index) in batch.enumerated() {
                        group.addTask {
                            let systems: [FoundSystem]
                            if let cached = BookLibrary.cachedSystems(book, index) {
                                systems = cached
                            } else if let fresh = BookImporter.page(docs[lane], index: index) {
                                BookLibrary.storePage(book, index, fresh.image, fresh.systems)
                                systems = fresh.systems
                            } else {
                                systems = []
                            }
                            return systems.isEmpty ? nil : index
                        }
                    }
                    var pages: Set<Int> = []
                    for await page in group { if let page { pages.insert(page) } }
                    return pages
                }
                // The nearest one in the batch, not the first to finish.
                found = batch.first(where: withMusic.contains)
                next += batch.count * step
            }
            let hit = found
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.seekingPage = nil
                if let hit {
                    self.show(page: hit)
                } else {
                    self.message = step > 0 ? "No more music after this page." : "No music before this page."
                }
            }
        }
    }

    /// Click: start a new selection at this system. Shift-click: extend to it.
    /// The name fills in from the page (the heading above the first line) unless the learner
    /// typed their own.
    func tapSystem(_ index: Int, extend: Bool) {
        guard phase != .reading else { return }
        canRetryRead = false
        if extend, let s = selection {
            selection = min(s.lowerBound, index)...max(s.upperBound, index)
        } else {
            selection = selection == index...index ? nil : index...index
        }
        resetSetup()
        checkClefs()
        let typed = title.trimmingCharacters(in: .whitespaces)
        guard typed.isEmpty || title == autoTitle else { return }
        autoTitle = savedForSelection?.title ?? selection.map { suggestedTitle(forLine: $0.lowerBound) } ?? ""
        title = autoTitle
    }

    /// Sets a line's box by hand (dragging its edges), where finding it on the page cut off part of
    /// the music or took in too much. Saved with the page, so it stays until the page is re-scanned.
    func resizeSystem(_ index: Int, to box: FoundSystem) {
        guard phase != .reading, let i = systems.firstIndex(where: { $0.index == index }) else { return }
        var box = box
        box.index = index
        guard box != systems[i] else { return }
        systems[i] = box
        resizedLines.insert(index)
        if !setupEdited { checkClefs() }
        if let book = documentURL { BookLibrary.storeSystems(book, pageIndex, systems) }
    }

    /// The saved piece read from exactly these lines, if there is one: Read opens it instead
    /// of reading again (unless "Ask Muse Wonder again" is on, or a line's box was just resized).
    var savedForSelection: SavedPiece? {
        guard let selection, let book = documentURL?.lastPathComponent,
              !setupEdited, !selection.contains(where: resizedLines.contains) else { return nil }
        return pieces.first {
            $0.book == book && $0.page == pageIndex && $0.firstLine == selection.lowerBound && $0.lastLine == selection.upperBound
                && FileManager.default.fileExists(atPath: $0.folder.appendingPathComponent("score.json").path)
        }
    }

    /// The name filled in from the page, so typing over it is noticed.
    private var autoTitle = ""

    /// The piece's name: the heading over the line (see `heading(on:above:)`), else
    /// "<book>, page N, line M" for a scan with no text.
    func suggestedTitle(forLine index: Int) -> String {
        let fallback = "\(documentURL?.deletingPathExtension().lastPathComponent ?? "Piece"), page \(pageIndex + 1), line \(index + 1)"
        guard systems.indices.contains(index), let page = document?.page(at: pageIndex) else { return fallback }
        return Self.heading(on: page, above: systems[index]) ?? fallback
    }

    /// The largest words in a line's top margin: a heading like "Exercise No. 12" (the composer,
    /// beside it, is smaller). Nil when there's none.
    static func heading(on page: PDFPage, above s: FoundSystem) -> String? {
        let box = page.bounds(for: .mediaBox)
        let k = 72 / BookImporter.dpi
        // Headings sit just above the top staff, around the top of the line's crop: take the page's
        // lines of text that start between a little above the crop and the staff, so a book title
        // higher up, and lyrics or text under the music, don't count. Only a line's top is used:
        // PDFKit makes some lines far too tall (a LilyPond heading reaches down past the staff),
        // which is also why `selection(for: rect)` finds nothing here.
        let from = box.maxY - CGFloat(Double(s.top) - 2.5 * s.spacing) * k
        let staffTop = box.maxY - CGFloat(Double(s.top) + 3.5 * s.spacing) * k
        let left = box.minX + CGFloat(s.left) * k, right = box.minX + CGFloat(s.right) * k
        let lines = (page.selection(for: box)?.selectionsByLine() ?? []).filter { line in
            let b = line.bounds(for: page)
            return (staffTop...from).contains(b.maxY) && b.maxX > left && b.minX < right
        }
        var best: (size: CGFloat, text: String) = (0, "")
        for line in lines {
            guard let text = line.attributedString, text.length > 0 else { continue }
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                guard let font = value as? NSFont else { return }
                let run = text.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
                // Time signatures and bar numbers are often the biggest type there.
                guard run.contains(where: \.isLetter) else { return }
                if font.pointSize > best.size + 0.5 { best = (font.pointSize, run) }
                else if abs(font.pointSize - best.size) <= 0.5, !best.text.contains(run) { best.text += " " + run }
            }
        }
        let name = best.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Too short to be a name (a dynamic) or a whole paragraph.
        return (3...80).contains(name.count) && best.size >= 11 ? name : nil
    }

    var canRead: Bool { selection != nil && phase != .reading }

    // MARK: Reading

    func read() {
        if !freshRead, let saved = savedForSelection {
            practise(saved)
            return
        }
        readSelection()
    }

    /// Reads the selected lines (from the saved readings, unless asked to read again), once
    /// their printed clefs have been looked at.
    private func readSelection() {
        guard let selection, let page = pageGray, let book = documentURL?.lastPathComponent else { return }
        guard !checkingClefs else {
            readWhenChecked = true
            return
        }
        // No key is fine as long as every line has a saved reading (see `finishReading`).
        // Separately: each staff is read as a line of its own, top staff first, in its own clef.
        var parts: [(found: FoundSystem, crop: FoundSystem, single: Bool, clef: SystemReading.Clef)] = []
        for i in selection where systems.indices.contains(i) {
            let s = systems[i]
            if layout == .separate {
                let middle = (s.top + s.bottom) / 2
                var upper = s, lower = s
                upper.bottom = middle
                lower.top = middle
                parts += [(s, upper, true, upperClef), (s, lower, true, lowerClef)]
            } else {
                parts.append((s, s, false, upperClef))
            }
        }
        let crops = parts.compactMap { part -> (FoundSystem, Gray, Data, NSImage, Bool, SystemReading.Clef)? in
            let crop = SystemFinder.crop(page, part.crop)
            guard let png = crop.pngData(), let cg = crop.cgImage() else { return nil }
            return (part.found, crop, png, NSImage(cgImage: cg, size: .zero), part.single, part.clef)
        }
        // Numbered after dropping any line that couldn't be cut out, so ids stay 0, 1, 2…
        startReading(crops.enumerated().map { k, c in
            // A staff read on its own is the reading's upper staff.
            SystemRead(id: k, found: c.0, gray: c.1, png: c.2, image: c.3, singleStaff: c.4, upperClef: c.5,
                       lowerClef: c.4 ? c.5 : lowerClef)
        }, source: PieceSource(book: book, page: pageIndex, lines: selection))
    }

    /// Reads these lines (the selection, cut from the page), replacing any read under way.
    func startReading(_ lines: [SystemRead], source: PieceSource) {
        cancelReading()
        aiKeyNote = nil
        self.source = source
        canRetryRead = false
        reads = lines
        bars = []
        clearReviewHistory()
        message = nil
        // Read in place, on the page: the check view opens only if a bar needs a look.
        phase = .reading
        let id = readID
        let jobs = reads.map { ($0.id, $0.png, $0.singleStaff) }
        let how: ReadingSource = savedReadingsOnly ? .savedOnly : freshRead ? .fresh : .saved
        freshRead = false  // just this once: the next piece uses saved readings again
        savedReadingsOnly = false
        let measure = measureLine, read = readLine
        readTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for (line, png, single) in jobs {
                    group.addTask {
                        await self.readSystem(line, png: png, singleStaff: single, how: how, readID: id,
                                              measure: measure, read: read)
                    }
                }
            }
            guard self.readID == id else { return }
            self.readTask = nil
            self.finishReading(how)
        }
    }

    /// Stops the read and any bars being read again; what they finish later is dropped.
    func cancelReading() {
        readID = UUID()
        readTask?.cancel()
        readTask = nil
        fixTasks.values.forEach { $0.cancel() }
        fixTasks = [:]
        fixing = []
    }

    /// How far the read of one line of the page has got, while reading: nil for a line not
    /// being read. A line read as two staves (right hand only) is as far as its slower staff.
    func readingStep(onLine index: Int) -> Step? {
        guard phase == .reading else { return nil }
        let steps = reads.filter { $0.found.index == index }.map(\.step)
        guard !steps.isEmpty else { return nil }
        if let failed = steps.first(where: { if case .failed = $0 { return true } else { return false } }) { return failed }
        for step in [Step.waiting, .measuring, .reading] where steps.contains(step) { return step }
        // Read: what's left is reading again any bars the first reading skipped.
        return fixing.isEmpty ? .done : .reading
    }

    /// The read's progress, 0...1, for the bar under the Read button.
    var readingProgress: Double {
        guard !reads.isEmpty else { return 0 }
        let done = reads.filter { $0.step == .done }.count
        // The lines take most of it; bars read again take the rest.
        return bars.isEmpty ? 0.9 * Double(done) / Double(reads.count) : (fixing.isEmpty ? 1 : 0.95)
    }

    // MARK: How the staves are read

    func choose(layout: Layout) {
        self.layout = layout
        setupEdited = true
    }

    func choose(upperClef: SystemReading.Clef) {
        self.upperClef = upperClef
        setupEdited = true
    }

    func choose(lowerClef: SystemReading.Clef) {
        self.lowerClef = lowerClef
        setupEdited = true
    }

    private func resetSetup() {
        layout = .together
        upperClef = .treble
        lowerClef = .treble
        setupUnclear = false
        setupEdited = false
        checkingClefs = false
        readWhenChecked = false
    }

    /// Fills in the setup from the clefs printed on the selected lines. A treble clef over a bass
    /// clef on every line is a grand staff, read together. Anything else (two treble clefs, or none
    /// printed: beginner books often print none) is a guess: the first line's clefs, a staff with
    /// none taken as treble, read together, for the learner to check.
    private func checkClefs() {
        guard let selection, let page = pageGray else { return }
        let crops = selection.compactMap { i in systems.indices.contains(i) ? SystemFinder.crop(page, systems[i]) : nil }
        checkingClefs = true
        Task.detached(priority: .userInitiated) {
            let printed = crops.map { NoteheadGeometry.printedClefs($0) }
            await MainActor.run {
                guard self.selection == selection, self.checkingClefs, !self.setupEdited else { return }
                self.checkingClefs = false
                let grand = !printed.isEmpty && printed.allSatisfy { $0 == (.treble, .bass) }
                self.layout = .together
                self.upperClef = printed.first?.upper ?? .treble
                self.lowerClef = printed.first?.lower ?? .treble
                self.setupUnclear = !grand
                if self.readWhenChecked {
                    self.readWhenChecked = false
                    self.read()
                }
            }
        }
    }

    private func readSystem(_ line: Int, png: Data, singleStaff: Bool, how: ReadingSource, readID: UUID,
                            measure: @escaping @Sendable (Data, Bool) throws -> NoteheadGeometry.System,
                            read: @Sendable (Data, Int, Bool, ReadingSource) async throws -> SystemReading) async {
        await setStep(line, .measuring, readID: readID)
        do {
            // Measure first (under a second): the bar count tells the model how many bars to read.
            let measured = try await Task.detached(priority: .userInitiated) { try measure(png, singleStaff) }.value
            await setStep(line, .reading, readID: readID)
            let reading = try await read(png, measured.barCount, singleStaff, how)
            await updateRead(line, readID: readID) {
                $0.reading = reading
                $0.geometry = measured
                $0.step = .done
            }
        } catch ModelError.missingKey(_) {
            await setStep(line, .failed(Self.keyNeededReason), readID: readID)
        } catch {
            await setStep(line, .failed((error as? LocalizedError)?.errorDescription ?? "\(error)"), readID: readID)
        }
    }

    @MainActor private func setStep(_ line: Int, _ step: Step, readID: UUID) {
        updateRead(line, readID: readID) { $0.step = step }
    }

    /// Changes one line of the read, if that read is still the current one.
    @MainActor private func updateRead(_ line: Int, readID: UUID, _ change: (inout SystemRead) -> Void) {
        guard self.readID == readID, let i = reads.firstIndex(where: { $0.id == line }) else { return }
        change(&reads[i])
    }

    private static let keyNeededReason = "it needs a Meta key"

    private func finishReading(_ how: ReadingSource) {
        if reads.contains(where: { $0.step == .failed(Self.keyNeededReason) }) {
            reads = []
            phase = .choosing
            if how == .savedOnly {
                afterReadingNote = nil
                message = "\(title) was saved before corrections were kept, and its saved reading has gone (the page has been "
                    + "scanned again since). To correct it, read it again from scratch (right-click it under Your pieces)."
            } else {
                aiKeyNote = "Reading a new piece needs a Meta key, which you can add in AI settings. Pieces you've already read, and the rest of Pebble Piano, work without one."
            }
            return
        }
        guard reads.allSatisfy({ $0.step == .done }) else {
            let why = reads.lazy.compactMap { r -> String? in if case .failed(let why) = r.step { return why } else { return nil } }.first
            message = "Some lines couldn't be read\(why.map { " (\($0))" } ?? ""). Check your connection and try again: "
                + "the lines that were read are kept."
            startOver()
            canRetryRead = true
            return
        }
        var out: [ReviewBar] = []
        for r in reads {
            guard let reading = r.reading, let geometry = r.geometry else { continue }
            let merged = BarMerge.merge(reading.withClefs(upper: r.upperClef, lower: r.lowerClef), geometry)
            for bar in merged {
                out.append(ReviewBar(id: out.count + 1, system: r.id, bar: bar, original: bar,
                                     resolution: bar.isTrusted ? .trusted : .needsReview,
                                     image: bar.pageBar.flatMap { barImage(r, $0) }))
            }
            engravingIDs[r.id] = UUID()
        }
        bars = out
        // Bars the reading skipped are read again one at a time, straight away, before deciding
        // whether anything needs the learner's eye. Not when only saved readings were to be used:
        // that's a call to Muse Wonder.
        let skipped = how == .savedOnly ? [] : out.filter { $0.bar.upperStatus == .flagged(.skippedByReading) }
        let rereads = skipped.compactMap { fix($0.id, fresh: false) }
        guard !rereads.isEmpty else { return finishChecking(how) }
        let id = readID
        Task { @MainActor in
            for task in rereads { await task.value }
            guard self.readID == id else { return }
            self.finishChecking(how)
        }
    }

    /// Every bar measured and read: saved and opened in Practice straight away when none needs a
    /// look, otherwise the check view opens on the bars that do. Checking a piece saved before
    /// checks were kept always opens the check view: that's what the learner asked for.
    private func finishChecking(_ how: ReadingSource) {
        guard phase == .reading else { return }
        if how != .savedOnly, toReview == 0, save() {
            // Back to the page, the piece's lines now tinted as read, for when the learner returns.
            startOver()
        } else {
            selectFirstToCheck()
            phase = .review
            message = afterReadingNote
            afterReadingNote = nil
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
                              singleStaff: Bool = false, fresh: Bool = false) async throws -> SystemReading {
        let url = cacheURL(png: png, expectedMeasures: expectedMeasures, singleStaff: singleStaff)
        let activeReader = reader ?? client.map { SystemReader(client: $0) }
        // Without a key a saved reading is still used, even when asked to read again.
        if !fresh || activeReader == nil, let data = try? Data(contentsOf: url),
           let cached = try? JSONDecoder().decode(SystemReading.self, from: data) {
            return cached
        }
        guard let activeReader else { throw ModelError.missingKey(.meta) }
        let reading = try await activeReader.read(png: png, expectedMeasures: expectedMeasures, singleStaff: singleStaff)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(reading).write(to: url)
        return reading
    }

    /// The key covers the image and how it was asked (v2: with the measured bar count; "-1staff"
    /// when read as one staff on its own).
    static func cacheURL(png: Data, expectedMeasures: Int?, singleStaff: Bool = false) -> URL {
        let key = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + "-v2-\(expectedMeasures ?? 0)"
            + (singleStaff ? "-1staff" : "")
        return cacheFolder.appendingPathComponent("\(key).json")
    }

    static var cacheFolder: URL { BookLibrary.support.appendingPathComponent("ReadingCache") }

    // MARK: Review

    var toReview: Int { bars.filter(\.needsReview).count }
    var canSave: Bool { phase != .choosing && !bars.isEmpty && toReview == 0 }

    func bars(inSystem s: Int) -> [ReviewBar] { bars.filter { $0.system == s } }

    /// The engraving of one system's bars, with the bars still to check tinted.
    func engraving(ofSystem s: Int) -> (score: Score, flagged: Set<Int>)? {
        let mine = bars(inSystem: s)
        guard !mine.isEmpty else { return nil }
        let piece = ScoreWriter.write(mine.map(\.bar), title: "", oneStaff: layout == .separate)
        let flagged = Set(mine.enumerated().filter { $0.element.needsReview }.map { $0.offset + 1 })
        return (piece.score, flagged)
    }

    // MARK: Correcting

    /// Opens a bar's card (nil closes it). A note picked in another bar is let go.
    func select(bar id: Int?) {
        guard id != selectedBar else { return }
        selectedBar = id
        selectedNote = nil
    }

    /// Picks a note of the selected bar (to move it, change it, delete it…), and plays it.
    func select(note: NoteRef?) {
        selectedNote = note
        if let note, let id = selectedBar { play(note, inBar: id) }
    }

    /// The next bar still to check after the selected one (round to the start), or the bar
    /// after it (`toCheck` false); `step` -1 goes back.
    func selectNext(toCheck: Bool, step: Int = 1) {
        guard !bars.isEmpty else { return }
        let start = bars.firstIndex { $0.id == selectedBar } ?? (step > 0 ? bars.count - 1 : 0)
        for offset in 1...bars.count {
            let i = ((start + step * offset) % bars.count + bars.count) % bars.count
            if !toCheck || bars[i].needsReview {
                select(bar: bars[i].id)
                return
            }
        }
    }

    private func selectFirstToCheck() {
        selectedBar = bars.first(where: \.needsReview)?.id
        selectedNote = nil
    }

    /// The learner checked the bar: it's right as it stands.
    func confirm(_ id: Int) {
        remember()
        update(id) { $0.resolution = .confirmed }
    }

    /// Back to checking: the bar was marked right (or corrected) too soon.
    func markToCheck(_ id: Int) {
        remember()
        update(id) { $0.resolution = .needsReview }
    }

    /// The bar as first read, every correction undone.
    func revert(_ id: Int) {
        guard let b = bars.first(where: { $0.id == id }), b.bar != b.original || b.resolution == .confirmed else { return }
        remember()
        update(id) { rb in
            rb.bar = rb.original
            rb.resolution = rb.original.isTrusted ? .trusted : .needsReview
        }
        selectedNote = nil
    }

    /// Moves one note up or down a line or space, and plays it.
    func nudge(_ id: Int, staff: SystemReading.StaffName, note k: Int, by delta: Int) {
        selectedNote = NoteRef(staff: staff, index: k)
        edit(id) { $0.move(staff, k, by: delta) }
    }

    func cycleAccidental(_ id: Int, _ note: NoteRef) {
        edit(id) { $0.cycleAccidental(note.staff, note.index) }
    }

    func setDuration(_ id: Int, _ note: NoteRef, _ duration: SystemReading.Duration) {
        edit(id) { $0.setDuration(note.staff, note.index, duration) }
    }

    func toggleDot(_ id: Int, _ note: NoteRef) {
        edit(id) { $0.toggleDot(note.staff, note.index) }
    }

    func toggleRest(_ id: Int, _ note: NoteRef) {
        edit(id) { $0.toggleRest(note.staff, note.index) }
    }

    /// Adds a note to a staff, after note `k` (at the end when nil), and picks it.
    func insertNote(_ id: Int, staff: SystemReading.StaffName, after k: Int?) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        let fallback = staffClef(inSystem: b.system, staff)
        var added = 0
        edit(id) { bar in
            added = bar.insertNote(staff, after: k ?? bar.notes(staff).count - 1, clef: fallback)
        }
        select(note: NoteRef(staff: staff, index: added))
    }

    func deleteNote(_ id: Int, _ note: NoteRef) {
        edit(id) { $0.deleteNote(note.staff, note.index) }
        selectedNote = nil
    }

    /// Reads one staff of a whole line in another clef (the clef printed at the start of the line
    /// was read wrong): every bar of the line changes, and counts as corrected.
    func setClef(inSystem system: Int, _ staff: SystemReading.StaffName, _ clef: SystemReading.Clef) {
        let ids = bars(inSystem: system).filter { !$0.bar.notes(staff).isEmpty && $0.bar.clef(staff, fallback: clef) != clef }.map(\.id)
        guard !ids.isEmpty else { return }
        remember()
        for id in ids {
            update(id) { rb in
                rb.bar.setClef(staff, clef)
                rb.resolution = .nudged
            }
        }
    }

    /// A staff's clef on a line: from its notes (upper treble and lower bass when it has none).
    func staffClef(inSystem system: Int, _ staff: SystemReading.StaffName) -> SystemReading.Clef {
        bars(inSystem: system).lazy.compactMap { $0.bar.notes(staff).first?.clef }.first ?? (staff == .upper ? .treble : .bass)
    }

    /// The metre the piece will be written in: what each bar should add up to.
    var metre: TimeSignature { ScoreWriter.metre(of: bars.map(\.bar)) }

    /// Changes one bar's notes, undoably: the bar then counts as corrected, and the picked note sounds.
    private func edit(_ id: Int, _ change: (inout BarMerge.Bar) -> Void) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        var bar = b.bar
        change(&bar)
        guard bar != b.bar else { return }
        remember()
        update(id) { rb in
            rb.bar = bar
            rb.resolution = .nudged
        }
        if let note = selectedNote, selectedBar == id { play(note, inBar: id) }
    }

    /// Plays a note as it sounds in its bar (a sharp or flat earlier in the bar still applies).
    private func play(_ note: NoteRef, inBar id: Int) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        let pitches = b.bar.midiPitches(note.staff)
        if pitches.indices.contains(note.index), let pitch = pitches[note.index] { session?.previewPitch(pitch) }
    }

    // MARK: Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Notes the review as it is, before a change.
    private func remember() {
        undoStack.append(snapshot)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack = []
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private var snapshot: ReviewSnapshot {
        ReviewSnapshot(bars: bars, selectedBar: selectedBar, selectedNote: selectedNote)
    }

    private func restore(_ s: ReviewSnapshot) {
        bars = s.bars
        selectedBar = s.selectedBar
        selectedNote = s.selectedNote
        for r in reads { engravingIDs[r.id] = UUID() }
    }

    private func clearReviewHistory() {
        undoStack = []
        redoStack = []
        proposals = [:]
        selectedBar = nil
        selectedNote = nil
    }

    /// Plays one bar, both hands, at a steady 80 bpm.
    func listen(_ id: Int) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        var notes: [(pitch: Int, start: Double, length: Double)] = []
        for staff in SystemReading.StaffName.allCases {
            var t = 0.0
            for (n, pitch) in zip(b.bar.notes(staff), b.bar.midiPitches(staff)) {
                let seconds = n.note.quarters * 60 / 80
                if let pitch { notes.append((pitch, t, seconds * 0.9)) }
                t += seconds
            }
        }
        session?.previewNotes(notes)
    }

    /// Asks Muse Wonder to read just this bar again (zoomed in), then measures and merges it.
    /// `fresh`: ask again rather than use a saved re-reading (the learner pressed Fix this bar;
    /// skipped bars re-read during a read use saved ones).
    /// A bar as first read takes the new reading (Revert brings the first back); a bar the
    /// learner corrected or checked gets it as a proposal instead (`proposals`).
    /// The task doing it, if it started (nil if it's already being read again, or can't be).
    @discardableResult
    func fix(_ id: Int, fresh: Bool = true) -> Task<Void, Never>? {
        guard !fixing.contains(id) else { return nil }  // already being read again
        guard let b = bars.first(where: { $0.id == id }), let r = reads.first(where: { $0.id == b.system }),
              let g = r.geometry else { return nil }
        guard let j = b.bar.pageBar, j + 1 < g.barEdges.count else {
            message = "Bar \(id) couldn't be found on the page, so it can't be read again. Correct its notes or tap That's right."
            return nil
        }
        guard let png = Self.barCrop(r.gray, g, bar: j).pngData() else { return nil }
        aiKeyNote = nil
        fixing.insert(id)
        let readID = self.readID, single = r.singleStaff, read = barReader
        // The bar's clefs are the line's (as read with the whole line in view, or as the learner
        // set them), not the model's guess from a crop that may not show them.
        let clefs = (upper: lineClef(b.system, .upper, g), lower: lineClef(b.system, .lower, g))
        fixTasks[id] = Task { @MainActor in
            let result: Result<BarMerge.Bar, Error>
            do {
                let reading = try await read(png, single, fresh)
                // Use the measure with the most notes (a crop can catch a sliver of a neighbour).
                guard var measure = reading.measures.max(by: {
                    $0.upper.notes.count + $0.lower.notes.count < $1.upper.notes.count + $1.lower.notes.count
                }) else { throw ModelError.badResponse("no bar in the reply") }
                measure.upper.clef = clefs.upper
                measure.lower.clef = clefs.lower
                var oneBar = g
                oneBar.barEdges = [g.barEdges[j], g.barEdges[j + 1]]
                var reread = BarMerge.merge(SystemReading(measureCount: 1, measures: [measure]), oneBar)[0]
                reread.pageBar = j
                result = .success(reread)
            } catch {
                result = .failure(error)
            }
            // Cancelled, or the piece changed while this bar was being read: drop it.
            guard self.readID == readID else { return }
            self.fixTasks[id] = nil
            self.fixing.remove(id)
            switch result {
            case .success(let merged):
                self.received(merged, forBar: id)
            case .failure(ModelError.missingKey):
                self.aiKeyNote = "Reading a bar again needs a Meta key, which you can add in AI settings. You can still correct its notes or tap That's right."
            case .failure(let error):
                self.message = "Couldn't re-read bar \(id): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            }
        }
        return fixTasks[id]
    }

    /// A bar read again: taken straight away if the bar is as first read, else proposed.
    private func received(_ reread: BarMerge.Bar, forBar id: Int) {
        guard let b = bars.first(where: { $0.id == id }) else { return }
        let untouched = b.bar == b.original && (b.resolution == .trusted || b.resolution == .needsReview)
        guard untouched else {
            proposals[id] = reread
            return
        }
        guard reread != b.bar else { return }
        remember()
        update(id) { rb in
            rb.bar = reread
            rb.resolution = reread.isTrusted ? .fixed : .needsReview
        }
        if phase == .review, bars.first(where: { $0.id == id })?.needsReview == true {
            message = "Bar \(id) still needs a look: correct any wrong note, then tap That's right."
        }
    }

    /// Takes the new reading of a bar in place of the learner's version (undoably).
    func useProposal(_ id: Int) {
        guard let reread = proposals.removeValue(forKey: id) else { return }
        remember()
        update(id) { rb in
            rb.bar = reread
            rb.resolution = reread.isTrusted ? .fixed : .needsReview
        }
        selectedNote = nil
    }

    /// Keeps the learner's version of a bar; the new reading is dropped.
    func dismissProposal(_ id: Int) {
        proposals[id] = nil
    }

    /// A staff's clef on a line: as its bars have it (read with the whole line in view, or set by
    /// the learner), else as measured at the start of the line.
    private func lineClef(_ system: Int, _ staff: SystemReading.StaffName, _ g: NoteheadGeometry.System) -> SystemReading.Clef {
        bars(inSystem: system).lazy.compactMap { $0.bar.notes(staff).first?.clef }.first
            ?? (staff == .upper ? g.upperClef : g.lowerClef)
    }

    /// What's sent to read bar `j` again: the bar, zoomed in by cropping it, with the start of the
    /// line (its clefs and time signature) beside it so the clefs aren't lost.
    static func barCrop(_ line: Gray, _ g: NoteheadGeometry.System, bar j: Int) -> Gray {
        let pad = Int(0.6 * g.upper.spacing)
        let x0 = max(0, Int(g.barEdges[j]) - pad)
        let x1 = min(line.width, Int(g.barEdges[j + 1]) + pad)
        func columns(_ from: Int, _ to: Int) -> Gray {
            SystemFinder.crop(line, FoundSystem(index: 0, left: from, top: 0, right: to, bottom: line.height, spacing: g.upper.spacing))
        }
        let start = min(Int(g.barEdges[0]), line.width)  // where the music starts, after the clefs
        guard start > 0 else { return columns(x0, x1) }
        guard x0 > start else { return columns(0, x1) }  // the first bar: the clefs are right there
        return SystemFinder.beside([columns(0, start), columns(x0, x1)], gap: pad)
    }

    private func update(_ id: Int, _ change: (inout ReviewBar) -> Void) {
        guard let i = bars.firstIndex(where: { $0.id == id }) else { return }
        change(&bars[i])
        engravingIDs[bars[i].system] = UUID()
    }

    /// Back to picking (cancelling a read under way), the lines still selected.
    func startOver() {
        aiKeyNote = nil
        cancelReading()
        phase = .choosing
        source = nil
        reads = []
        bars = []
        clearReviewHistory()
    }

    // MARK: Saving

    /// Writes the piece and opens it in Practice. False if it couldn't.
    @discardableResult
    func save() -> Bool {
        guard let saved = store() else { return false }
        practise(saved)
        // After opening it, which clears Practice's message.
        if let note = lessonNote { session?.message = note }
        lessonNote = nil
        return true
    }

    /// Said once the piece opens in Practice, when saving it changed notes its lesson was made from.
    private(set) var lessonNote: String?

    /// Writes the piece (MIDI, MusicXML, score) and its check (`PieceCorrection`), so it can be
    /// checked again as it was left. A piece already saved from these lines is replaced, in its
    /// own folder, whatever it's called now.
    @discardableResult
    func store() -> SavedPiece? {
        guard canSave, let source else { return nil }
        let existing = savedPiece(for: source)
        let typed = title.trimmingCharacters(in: .whitespaces)
        let name = !typed.isEmpty ? typed
            : existing?.title ?? reads.first.map { suggestedTitle(forLine: $0.found.index) } ?? "Piece"
        let piece = ScoreWriter.write(bars.map(\.bar), title: name, oneStaff: layout == .separate)
        let saved = SavedPiece(id: existing?.id ?? BookLibrary.pieceID(book: source.book, page: source.page, lines: source.lines),
                               title: name, book: source.book, page: source.page,
                               firstLine: source.lines.lowerBound, lastLine: source.lines.upperBound, created: Date())
        let folder = saved.folder
        let before = (try? Data(contentsOf: folder.appendingPathComponent("score.json")))
            .flatMap { try? JSONDecoder().decode(Score.self, from: $0) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try piece.midi.write(to: folder.appendingPathComponent("piece.mid"))
            try Data(piece.musicXML.utf8).write(to: folder.appendingPathComponent("piece.musicxml"))
            try JSONEncoder().encode(piece.score).write(to: folder.appendingPathComponent("score.json"))
            try JSONEncoder().encode(piece.printedFingering).write(to: folder.appendingPathComponent("fingering.json"))
            try BookLibrary.storeCorrection(correction, lineImages: reads.map(\.png), in: folder)
            try BookLibrary.store(saved)
            // Corrected notes: the lesson made from the old ones goes, to be made again.
            lessonNote = nil
            if let before {
                let changed = Self.changedBars(before, piece.score)
                if !changed.isEmpty {
                    PieceLessonStore.forgetLesson(saved.id)
                    lessonNote = "Your corrections changed \(Self.barList(changed)) of \(name), so its lesson will be planned "
                        + "again from the corrected notes."
                }
            }
            message = nil
            refreshLibrary()
            return saved
        } catch {
            message = "Couldn't save the piece: \(error.localizedDescription)"
            return nil
        }
    }

    /// Bar numbers (from 1) whose notes or rests differ between two versions of a piece; bars
    /// only one of them has count too.
    static func changedBars(_ old: Score, _ new: Score) -> [Int] {
        (0..<max(old.measures.count, new.measures.count)).filter { i in
            !old.measures.indices.contains(i) || !new.measures.indices.contains(i)
                || old.measures[i].events != new.measures[i].events
        }.map { $0 + 1 }
    }

    /// "bar 3", "bars 3 and 5", "bars 2, 3 and 7".
    static func barList(_ bars: [Int]) -> String {
        let names = bars.map(String.init)
        guard names.count > 1 else { return "bar \(names.first ?? "")" }
        return "bars " + names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// The check as it stands: every line read and every bar, for saving.
    var correction: PieceCorrection {
        PieceCorrection(
            oneStaff: layout == .separate,
            lines: reads.map { .init(found: $0.found, singleStaff: $0.singleStaff, reading: $0.reading, geometry: $0.geometry) },
            bars: bars.map { b in
                .init(line: reads.firstIndex { $0.id == b.system } ?? 0, bar: b.bar, original: b.original, resolution: b.resolution)
            })
    }

    /// The saved piece read from these lines, if there is one (the newest, should there be two).
    func savedPiece(for source: PieceSource) -> SavedPiece? {
        pieces.first { $0.book == source.book && $0.page == source.page
            && $0.firstLine == source.lines.lowerBound && $0.lastLine == source.lines.upperBound }
    }

    // MARK: Saved pieces

    /// Opens a saved piece in Practice, as it was read and checked: no reading again.
    func practise(_ piece: SavedPiece) {
        do {
            let score = try JSONDecoder().decode(Score.self, from: Data(contentsOf: piece.folder.appendingPathComponent("score.json")))
            session?.tab = .practice
            session?.loadReference(piece.folder.appendingPathComponent("piece.mid"), remember: false, writtenScore: score,
                                   printedFingering: BookLibrary.printedFingering(of: piece))
            // A tutor lesson under way on this piece carries on where it was left.
            if let progress = session?.savedTutorProgress, !progress.mastered {
                session?.beginTutoring(planLesson: true)
            }
        } catch {
            message = "Couldn't open \(piece.title): \(error.localizedDescription)"
        }
    }

    /// Loads a saved piece by its MIDI file, as it was read and checked, staying on this tab.
    /// False if `url` isn't a saved piece (or it can't be read). A tutor lesson on it isn't
    /// reopened: its Continue is there for when the learner wants it.
    func restoreSavedPiece(at url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard let piece = pieces.first(where: { $0.folder.appendingPathComponent("piece.mid").standardizedFileURL.path == path }),
              let data = try? Data(contentsOf: piece.folder.appendingPathComponent("score.json")),
              let score = try? JSONDecoder().decode(Score.self, from: data) else { return false }
        session?.loadReference(url, remember: false, writtenScore: score, printedFingering: BookLibrary.printedFingering(of: piece))
        return true
    }

    /// Reopens a saved piece's check as it was left: its bars and every correction, ready to
    /// correct more and save again. Nothing is read again, so no key is needed. A piece saved
    /// before checks were kept opens from its saved readings instead, as first read.
    func correct(_ piece: SavedPiece) {
        aiKeyNote = nil
        message = nil
        guard let (stored, images) = BookLibrary.correction(of: piece) else {
            correctFromReadings(piece)
            return
        }
        cancelReading()
        title = piece.title
        resetSetup()
        layout = stored.oneStaff ? .separate : .together
        setupEdited = true
        source = PieceSource(book: piece.book, page: piece.page, lines: piece.firstLine...piece.lastLine)
        reads = zip(stored.lines, images).enumerated().map { k, pair in
            let (line, image) = pair
            return SystemRead(id: k, found: line.found, gray: image.gray, png: image.png,
                              image: image.gray.cgImage().map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(),
                              singleStaff: line.singleStaff, step: .done, reading: line.reading, geometry: line.geometry)
        }
        bars = stored.bars.enumerated().map { i, b in
            ReviewBar(id: i + 1, system: b.line, bar: b.bar, original: b.original, resolution: b.resolution,
                      image: b.bar.pageBar.flatMap { barImage(reads[b.line], $0) })
        }
        for r in reads { engravingIDs[r.id] = UUID() }
        clearReviewHistory()
        selectFirstToCheck()
        phase = .review
    }

    /// A piece saved before its check was kept: goes to its page and reads its lines from the
    /// saved readings (free; no key needed), as they were first read.
    private func correctFromReadings(_ piece: SavedPiece) {
        guard let book = library.first(where: { $0.url.lastPathComponent == piece.book }) else {
            message = "Open \(piece.book) first: it isn't in your books."
            return
        }
        title = piece.title
        let score = (try? Data(contentsOf: piece.folder.appendingPathComponent("score.json")))
            .flatMap { try? JSONDecoder().decode(Score.self, from: $0) }
        // Read as it was saved: its layout, and the clefs its staves were written in.
        let staves = score?.staves ?? []
        let clef = { (i: Int) -> SystemReading.Clef in staves.indices.contains(i) && staves[i] == .bass ? .bass : .treble }
        pendingCorrection = (lines: piece.firstLine...piece.lastLine, layout: staves.count == 1 ? .separate : .together,
                             upper: clef(0), lower: staves.count == 1 ? clef(0) : clef(1))
        afterReadingNote = "\(piece.title) was saved before corrections were kept, so it opens as it was first read: "
            + "make any corrections again, then save."
        open(book.url, page: piece.page)
    }

    /// Goes back to the piece's page with its lines selected and "Ask Muse Wonder again" on, to
    /// read it afresh. Saving the new reading replaces the piece and its corrections.
    func readAgainFromScratch(_ piece: SavedPiece) {
        guard let book = library.first(where: { $0.url.lastPathComponent == piece.book }) else {
            message = "Open \(piece.book) first: it isn't in your books."
            return
        }
        title = piece.title
        pendingSelection = piece.firstLine...piece.lastLine
        open(book.url, page: piece.page)
        freshRead = true
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
