#if os(macOS)
import AppKit
import Foundation
import PDFKit
import PianoLessons

/// Ask your tutor: questions about music, with the lesson and its book page as context.
/// Adults only: a child never sees it, and nothing is sent for one.
extension PlaySession {
    var canChatWithTutor: Bool { learner?.kind == .adult }

    func sendTutorChat(_ text: String) {
        guard canChatWithTutor, let question = TutorChat.clean(text) else { return }
        stopTutorChat()
        tutorChatNote = nil
        let client: any TutorChatClient
        do {
            client = try tutorChatClient ?? makeTutorChatClient()
        } catch {
            tutorChatNote = "Asking your tutor needs a Meta key, which you can add in AI settings."
            return
        }
        let history = tutorChat.history
        let id = tutorChat.ask(question)
        let context = tutorChatContext(for: question)
        let generation = UUID()
        tutorChatGeneration = generation
        tutorChatBusy = true
        tutorChatTask = Task { @MainActor [weak self] in
            do {
                let reply = try await client.reply(history: history, context: context, question: question)
                guard let self, !Task.isCancelled, self.tutorChatGeneration == generation, self.canChatWithTutor else { return }
                self.tutorChat.answer(reply, to: id)
                self.tutorChatBusy = false
            } catch {
                guard let self, self.tutorChatGeneration == generation else { return }
                self.tutorChat.withdraw(id)
                self.tutorChatBusy = false
                if !Task.isCancelled { self.tutorChatNote = "Couldn't reach your tutor just now. Try again in a moment." }
            }
        }
    }

    /// Stops waiting for an answer; the question is taken back.
    func stopTutorChat() {
        tutorChatTask?.cancel()
        tutorChatGeneration = UUID()
        tutorChatBusy = false
        if let last = tutorChat.turns.last, last.role == .learner { tutorChat.withdraw(last.id) }
    }

    /// A new conversation (and none at all for a child: see `learner`).
    func resetTutorChat() {
        stopTutorChat()
        tutorChat.clear()
        tutorChatNote = nil
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
        guard tutorChatUsesBook, let book = tutorChatBook() else { return context }
        let texts = Self.pageTexts(of: book.document)
        let near = Set((book.page - 1)...(book.page + 1)).filter { texts.indices.contains($0) }
        let matching = BookTextSearch.best(for: question, in: texts, excluding: near)
        context.bookTitle = book.title
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
