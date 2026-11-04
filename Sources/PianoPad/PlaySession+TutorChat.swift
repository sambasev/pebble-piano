#if os(macOS)
import AppKit
import Foundation
import PDFKit
import PianoLessons

/// A settings change the tutor offered, waiting for the learner's tap.
struct TutorChatConfirmation: Equatable {
    var label: String
    var action: TutorChatAction
}

enum TutorChatPanel: String, Equatable { case input, practice, ai }

struct TutorChatObservation {
    var label: String
    var question: String
    var context: TutorChatContext
    var scoreID: UUID
}

/// Ask your tutor: questions about music, with the lesson and its book page as context.
/// Adults type freely; a child only taps `TutorChildPrompts` (C6).
extension PlaySession {
    /// Free questions: adults only.
    var canChatWithTutor: Bool { learner?.kind == .adult }
    /// Any tutor chat at all: an adult, or a child with the fixed questions.
    var canAskTutor: Bool { learner?.kind == .adult || learner?.kind == .child }
    var tutorChatIsChild: Bool { learner?.kind == .child }

    /// A child's (or their grown-up's) tap on a fixed question. Nothing else is ever sent for a child.
    func askTutorAsChild(_ chip: String) {
        guard tutorChatIsChild, let audience = TutorChildPrompts.audience(for: chip) else { return }
        stopTutorChat()
        let question = TutorChildPrompts.question(for: chip)
        var context = tutorChatContext(for: question)
        context.audience = audience
        requestTutorChat(question, context: context, observation: nil, scoreID: scoreID, shown: chip)
    }

    func sendTutorChat(_ text: String) {
        guard canChatWithTutor, let question = TutorChat.clean(text) else { return }
        stopTutorChat()
        requestTutorChat(question, context: tutorChatContext(for: question), observation: nil, scoreID: scoreID)
    }

    func requestTutorChat(_ question: String, context: TutorChatContext, observation: String?, scoreID: UUID,
                          shown: String? = nil) {
        guard canAskTutor, canChatWithTutor || context.audience != .adult else { return }
        tutorChatNote = nil
        let client: any TutorChatClient
        do {
            client = try tutorChatClient ?? makeTutorChatClient()
        } catch {
            tutorChatNote = "Asking your tutor needs a Meta key, which you can add in AI settings."
            return
        }
        let history = tutorChat.history
        let id = observation.map { tutorChat.observe($0) } ?? tutorChat.ask(shown ?? question)
        tutorChatRequestTurn = id
        let generation = UUID()
        tutorChatGeneration = generation
        tutorChatBusy = true
        tutorChatTask = Task { @MainActor [weak self] in
            do {
                let reply = try await client.reply(history: history, context: context, question: question, partial: { text in
                    Task { @MainActor [weak self] in
                        guard let self, self.tutorChatGeneration == generation, self.tutorChatBusy else { return }
                        self.tutorChatStreamingText = text
                    }
                })
                self?.tutorChatStreamingText = nil
                guard let self, !Task.isCancelled, self.tutorChatGeneration == generation, self.canAskTutor else { return }
                self.tutorChat.answer(reply, to: id)
                self.tutorChatBusy = false
                self.tutorChatRequestTurn = nil
                self.tutorChatTask = nil
                if reply.onTopic, !reply.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // A grown-up's question gets an answer only; a child's, only the child actions.
                    let actions = context.audience == .grownUp ? []
                        : context.audience == .child ? reply.actions.filter { TutorChildPrompts.actions.contains($0.kind) }.prefix(2).map { $0 }
                        : Array(reply.actions.prefix(TutorChatReply.actionLimit))
                    self.runTutorChatPlan(actions, scoreID: scoreID)
                }
                self.saveTutorChat()
                self.flushTutorChatObservation()
            } catch {
                guard let self, self.tutorChatGeneration == generation else { return }
                self.tutorChatStreamingText = nil
                self.tutorChat.withdraw(id)
                self.tutorChatBusy = false
                self.tutorChatRequestTurn = nil
                self.tutorChatTask = nil
                if !Task.isCancelled { self.tutorChatNote = "Couldn't reach your tutor just now. Try again in a moment." }
                self.flushTutorChatObservation()
            }
        }
    }

    /// Runs a reply's first action now and queues the rest. A failed step drops what's left.
    func runTutorChatPlan(_ actions: [TutorChatAction], scoreID: UUID) {
        tutorChatQueuedActions = []
        tutorChatQueueScoreID = nil
        var remaining = actions[...]
        while let action = remaining.popFirst() {
            // Checked before the step runs: practiceExercise opens new music by design.
            let current = self.scoreID == scoreID || action.kind == .stop || action.kind == .setGoal
            let outcome = current
                ? applyTutorChatAction(action)
                : "The music changed while I was answering, so I left the player alone. Ask again about the current music."
            let ran = tutorChatActionRan && current
            recordTutorChatOutcome(outcome)
            guard ran, !remaining.isEmpty else {
                if !remaining.isEmpty { recordTutorChatOutcome(Self.skippedSteps(remaining.count)) }
                return
            }
            if action.endsPlan {
                recordTutorChatOutcome(Self.skippedSteps(remaining.count))
                return
            }
            if action.waitsForPlayer {
                tutorChatQueuedActions = Array(remaining)
                tutorChatQueueScoreID = self.scoreID
                return
            }
        }
    }

    /// The next queued step, when the one before it has finished. False when nothing is queued
    /// (the tutor is asked as usual) or the music changed (the plan is dropped).
    func advanceTutorChatPlan() -> Bool {
        guard canChatWithTutor, !tutorChatQueuedActions.isEmpty else { return false }
        defer { saveTutorChat() }
        guard tutorChatQueueScoreID == scoreID else {
            recordTutorChatOutcome(Self.skippedSteps(tutorChatQueuedActions.count))
            tutorChatQueuedActions = []
            tutorChatQueueScoreID = nil
            return false
        }
        runTutorChatPlan(tutorChatQueuedActions, scoreID: scoreID)
        return true
    }

    private func recordTutorChatOutcome(_ outcome: String) {
        tutorChatActionResults = Array((tutorChatActionResults + [outcome]).suffix(6))
        tutorChat.observe(outcome)
    }

    static func skippedSteps(_ count: Int) -> String {
        "Skipped the \(count == 1 ? "next step" : "\(count) remaining steps") of my plan."
    }

    /// Stops waiting for an answer; the question is taken back.
    func stopTutorChat() {
        tutorChatTask?.cancel()
        tutorChatGeneration = UUID()
        tutorChatBusy = false
        tutorChatStreamingText = nil
        if let id = tutorChatRequestTurn { tutorChat.withdraw(id) }
        tutorChatRequestTurn = nil
        tutorChatTask = nil
        tutorChatPendingObservation = nil
        tutorChatQueuedActions = []
        tutorChatQueueScoreID = nil
        tutorChatConfirmation = nil
    }

    /// A new conversation (and none at all for a child: see `learner`). The one that ends gets a
    /// note in the learner's tutor memory, unless it's `keepSaved` to reopen later.
    func resetTutorChat(keepSaved: Bool = false) {
        stopTutorChat()
        if !keepSaved, let owner = tutorChatOwner {
            if TutorChatMemory.isWorthNoting(tutorChat.turns) { noteTutorChat(tutorChat.turns, learner: owner, piece: tutorTitle) }
            try? tutorChatMemory(for: owner).save(piece: nil, turns: [])
        }
        tutorChatOwner = nil
        tutorChat.clear()
        tutorChatNote = nil
        tutorChatCoaching = false
        tutorChatAwaitingStart = false
        tutorChatOffersGrade = false
        tutorChatActionResults = []
        tutorChatRecentGrades = []
        tutorChatFocus = ""
        tutorChatFoundPieces = [:]
        tutorChatLatestSearch = []
    }

    // MARK: Memory

    func tutorChatMemory(for learner: UUID) -> TutorChatMemory {
        TutorChatMemory(folder: learnerStore.folder(for: learner).appendingPathComponent("tutor", isDirectory: true))
    }

    /// Keeps the conversation in the learner's folder, to reopen with this piece. A conversation
    /// saved for another piece is noted before it's replaced.
    func saveTutorChat() {
        guard canAskTutor, let learner, !tutorChat.turns.isEmpty else { return }
        let memory = tutorChatMemory(for: learner.id)
        let piece = currentPieceID?.rawValue
        if tutorChatOwner == nil, let old = memory.chat(), old.piece != piece, TutorChatMemory.isWorthNoting(old.turns) {
            noteTutorChat(old.turns, learner: learner.id, piece: "an earlier piece")
        }
        tutorChatOwner = learner.id
        try? memory.save(piece: piece, turns: tutorChat.turns)
    }

    /// Reopens the conversation saved with the open piece, if there's no conversation yet.
    func restoreTutorChat() {
        tutorChatSessionPlan = canChatWithTutor ? learner.flatMap { tutorChatMemory(for: $0.id).plan() } : nil
        guard canAskTutor, let learner, tutorChat.turns.isEmpty, !tutorChatBusy,
              let turns = tutorChatMemory(for: learner.id).chat(for: currentPieceID?.rawValue) else { return }
        tutorChat = TutorChat(turns: turns)
        tutorChatOwner = learner.id
    }

    /// A few lines about a finished conversation: the model's summary, else the questions asked.
    func noteTutorChat(_ turns: [TutorChatTurn], learner: UUID, piece: String) {
        let memory = tutorChatMemory(for: learner)
        let client = try? tutorChatClient ?? makeTutorChatClient()
        let piece = piece.isEmpty ? "no piece open" : piece
        Task {
            let summary = (try? await client?.summarize(turns)) ?? nil
            try? memory.add(TutorChatNote(date: Date(), piece: piece, text: summary ?? TutorChatMemory.fallbackNote(turns)))
        }
    }

    // MARK: Context

    /// The lesson, and (unless turned off) the book page: its text and its neighbours', the pages
    /// matching the question, and a picture of it.
    func tutorChatContext(for question: String) -> TutorChatContext {
        var lesson = reference?.notes.isEmpty == false || score != nil ? "Piece: \(tutorTitle)." : ""
        if let instructions = passage?.instructions { lesson += " The book says: \(instructions)" }
        if let piece = tutorChatSavedPiece {
            let lines = piece.firstLine == piece.lastLine ? "line \(piece.firstLine + 1)" : "lines \(piece.firstLine + 1)–\(piece.lastLine + 1)"
            lesson += " It is \(lines) of music on page \(piece.page + 1), counting from the top."
        }
        let tutorSoFar = tutorContext.isEmpty ? tutorText : tutorContext
        if !tutorSoFar.isEmpty { lesson += " " + tutorSoFar }
        var context = TutorChatContext(lesson: lesson.trimmingCharacters(in: .whitespaces))
        addTutorChatEvidence(to: &context, question: question)
        if canChatWithTutor { context.library = MainActor.assumeIsolated { tutorChatLibraryText() } }
        if let learner { context.previousSessions = TutorChatMemory.prompt(tutorChatMemory(for: learner.id).notes()) }
        if TutorAppGuide.isAppQuestion(question) || tutorChatFewNotesDetected {
            context.appGuide = TutorAppGuide.text
            context.diagnostics = tutorChatDiagnostics
        }
        guard tutorChatUsesBook, let book = tutorChatBook() else { return context }
        let texts = Self.pageTexts(of: book.document)
        let near = Set((book.page - 1)...(book.page + 1)).filter { texts.indices.contains($0) }
        let matching = BookTextSearch.best(for: question, in: texts, excluding: near)
        context.bookTitle = LibraryBook.displayTitle(book.title)
        context.currentPage = book.page + 1
        context.pages = (near.sorted() + matching).compactMap { i in
            let text = BookTextSearch.excerpt(texts[i])
            return text.isEmpty ? nil : TutorChatContext.Page(number: i + 1, text: text)
        }
        context.pageImage = book.document.page(at: book.page).flatMap(Self.jpeg)
        return context
    }

    /// The book the open piece came from, and its page (from 0): a book passage, or a piece read
    /// from a book in the Books tab.
    func tutorChatBook() -> (document: PDFDocument, title: String, page: Int)? {
        if let book, let passage {
            return (book.document, book.annotations.title, passage.page - 1)
        }
        guard let piece = tutorChatSavedPiece,
              let source = BookLibrary.books().first(where: { $0.url.lastPathComponent == piece.book }),
              let document = PDFDocument(url: source.url) else { return nil }
        return (document, source.title, piece.page)
    }

    /// The saved piece open in Practice, if it was read from a book. Looked up once per piece.
    var tutorChatSavedPiece: SavedPiece? {
        guard let path = referenceURL?.standardizedFileURL.path else { return nil }
        if let cached = Self.savedPieceCache, cached.path == path { return cached.piece }
        let piece = BookLibrary.pieces().first { $0.folder.appendingPathComponent("piece.mid").standardizedFileURL.path == path }
        Self.savedPieceCache = (path, piece)
        return piece
    }

    private static var savedPieceCache: (path: String, piece: SavedPiece?)?

    /// Every page's text, kept for the last book asked about (a book's text doesn't change).
    private static var pageTextCache: (url: URL?, pages: [String])?

    static func pageTexts(of document: PDFDocument) -> [String] {
        if let cached = pageTextCache, cached.url != nil, cached.url == document.documentURL { return cached.pages }
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        pageTextCache = (document.documentURL, pages)
        return pages
    }

    /// A page as a JPEG about 1400 pixels wide: enough to read the music, small enough to send.
    static func jpeg(_ page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let scale = 1400 / bounds.width
        let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
#endif
