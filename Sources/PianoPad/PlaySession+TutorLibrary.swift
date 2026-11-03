#if os(macOS)
import Foundation
import PDFKit
import PianoCatalog
import PianoGraderCore
import PianoLessons
import PianoPadState

/// Something the tutor found for the learner to open: a Music Library piece, a goal song, a book
/// passage, a piece read from a book, or a recent file. Its `id` is what `openPiece` accepts.
struct TutorLibraryItem: Equatable {
    enum Source: Equatable {
        case catalog(CatalogPiece)
        case goalSong(GoalSong)
        case passage(PassageAnnotation)
        case saved(SavedPiece)
        case recent(RecentPiece)
    }

    var id: String
    var title: String
    var composer: String?
    var difficulty: CatalogPiece.Difficulty?
    var source: Source

    var place: String {
        switch source {
        case .catalog: return "Music Library"
        case .goalSong: return "goal song"
        case .passage: return "book passage"
        case .saved: return "piece read from a book"
        case .recent: return "recent piece"
        }
    }

    /// One line for the chat: "[catalog:mutopia-61] Minuet in G — J. S. Bach · Elementary · Music Library".
    var line: String {
        "[\(id)] \(title)" + (composer.map { " — \($0)" } ?? "")
            + " · \(difficulty?.rawValue ?? "level not rated") · \(place)"
    }
}

// Library and navigation actions for Ask your tutor. Searching is local (no model call); opening
// accepts only an ID a search returned in this conversation, checked again against live state.
// The Music Library model is main-actor; PlaySession callers bridge with `MainActor.assumeIsolated`.
@MainActor
extension PlaySession {
    static let tutorLibraryResultLimit = 5

    // MARK: Search

    /// Everything the learner could open now, personal music first.
    func tutorLibraryCandidates() -> [TutorLibraryItem] {
        var items: [TutorLibraryItem] = []
        for piece in learnerSettings.recentPieces {
            let title = Self.tutorRecentTitle(piece)
            let catalog = musicLibrary.pieces.first { $0.title == piece.title }
            items.append(.init(id: "recent:" + piece.id.rawValue, title: title, composer: catalog?.composer,
                               difficulty: catalog?.difficulty, source: .recent(piece)))
        }
        let chosen = learnerSettings.goalSong ?? GoalSongs.defaultID
        for song in GoalSongs.all.sorted(by: { a, _ in a.id == chosen }) {
            items.append(.init(id: "goal:" + song.id, title: song.title, composer: nil, difficulty: .elementary, source: .goalSong(song)))
        }
        for p in book?.annotations.passages ?? [] {
            let level: CatalogPiece.Difficulty? = p.rubric == "intermediate" ? .intermediate : p.rubric == "beginner" || p.rubric == nil ? .elementary : nil
            items.append(.init(id: "passage:" + p.id, title: p.title, composer: book?.annotations.title, difficulty: level, source: .passage(p)))
        }
        for piece in BookLibrary.pieces() {
            items.append(.init(id: "book:" + piece.id, title: piece.title, composer: nil, difficulty: nil, source: .saved(piece)))
        }
        for piece in musicLibrary.pieces {
            items.append(.init(id: "catalog:" + piece.id, title: piece.title, composer: piece.composer,
                               difficulty: piece.difficulty, source: .catalog(piece)))
        }
        return items
    }

    static func tutorRecentTitle(_ piece: RecentPiece) -> String {
        piece.title.map { pieceName(URL(fileURLWithPath: piece.path ?? ""), title: $0) }
            ?? piece.path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Recent piece"
    }

    /// The best matches: every query word in the title or composer, the composer and level
    /// filters, then exact titles, the learner's own music, and their level first.
    static func tutorLibraryRank(_ items: [TutorLibraryItem], query: String, composer: String?,
                                 difficulty: CatalogPiece.Difficulty?, suggested: CatalogPiece.Difficulty?) -> [TutorLibraryItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let composer = composer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var seen = Set<String>()
        let scored = items.enumerated().compactMap { index, item -> (item: TutorLibraryItem, score: Int, index: Int)? in
            let text = item.title + " " + (item.composer ?? "")
            guard words.allSatisfy({ text.localizedStandardContains($0) }),
                  composer.map({ item.composer?.localizedStandardContains($0) == true }) ?? true,
                  difficulty.map({ item.difficulty == $0 }) ?? true,
                  seen.insert(item.title.lowercased() + "|" + (item.composer ?? "").lowercased()).inserted else { return nil }
            var score = 0
            if !words.isEmpty, words.allSatisfy({ item.title.localizedStandardContains($0) }) { score += 2 }
            if item.title.compare(query.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { score += 3 }
            switch item.source {
            case .recent, .goalSong, .passage, .saved: score += 1
            case .catalog: break
            }
            if let suggested, item.difficulty == suggested { score += 1 }
            return (item, score, index)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .prefix(tutorLibraryResultLimit).map(\.item)
    }

    /// The catalog level that suits what the learner has shown (`LearnerSkills`), never above Intermediate.
    static func tutorSuggestedLevel(_ skills: LearnerSkills) -> CatalogPiece.Difficulty {
        skills.playedHandsTogether && skills.passedTitles.count >= 3 && (skills.fastestTempo ?? 0) >= 96
            ? .intermediate : .elementary
    }

    func tutorChatSearchLibrary(_ action: TutorChatAction) -> (outcome: String, ran: Bool) {
        let query = (action.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 200 else { return ("That search is too long. Ask for a title or composer.", false) }
        var level: CatalogPiece.Difficulty?
        if let raw = action.difficulty?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            guard let found = CatalogPiece.Difficulty.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) else {
                return ("Difficulty must be Elementary, Intermediate or Advanced.", false)
            }
            level = found
        }
        let composer = action.composer.map { String($0.prefix(100)) }
        let results = Self.tutorLibraryRank(tutorLibraryCandidates(), query: query, composer: composer, difficulty: level,
                                            suggested: Self.tutorSuggestedLevel(learnerSkills()))
        let filters = [query.isEmpty ? nil : "“\(query)”", composer.map { "by \($0)" }, level?.rawValue].compactMap { $0 }
        let label = filters.isEmpty ? "Library" : "Library search " + filters.joined(separator: ", ")
        guard !results.isEmpty else { return ("\(label): nothing matched. No music was opened.", false) }
        for item in results { tutorChatFoundPieces[item.id] = item }
        tutorChatLatestSearch = results.map(\.id)
        let lines = results.enumerated().map { "#\($0.offset + 1) \($0.element.line)" }
        return ("\(label), top \(results.count):\n" + lines.joined(separator: "\n"), true)
    }

    // MARK: Opening

    /// A found item, still present: "#2" is the latest search's second result.
    func tutorChatFoundItem(_ ref: String?) -> TutorLibraryItem? {
        guard let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }
        var id = ref
        if ref.hasPrefix("#"), let n = Int(ref.dropFirst()) {
            guard tutorChatLatestSearch.indices.contains(n - 1) else { return nil }
            id = tutorChatLatestSearch[n - 1]
        }
        guard let item = tutorChatFoundPieces[id] else { return nil }
        switch item.source {
        case .catalog(let piece): return musicLibrary.pieces.contains(piece) ? item : nil
        case .goalSong(let song): return GoalSongs.song(song.id) != nil ? item : nil
        case .passage(let p): return book?.annotations.passages.contains { $0.id == p.id } == true ? item : nil
        case .saved(let piece): return FileManager.default.fileExists(atPath: piece.folder.appendingPathComponent("piece.mid").path) ? item : nil
        case .recent(let piece): return learnerSettings.recentPieces.contains { $0.id == piece.id } ? item : nil
        }
    }

    static let tutorUnknownPiece = "I can only open music a library search found in this chat. Ask me to search first; nothing was opened."

    func tutorChatOpenPiece(_ action: TutorChatAction) -> (outcome: String, ran: Bool) {
        guard let item = tutorChatFoundItem(action.pieceRef) else { return (Self.tutorUnknownPiece, false) }
        let before = scoreID
        tutorChatPreservesConversation = true
        defer { tutorChatPreservesConversation = false }
        switch item.source {
        case .catalog(let piece):
            let learnerID = learner?.id
            musicLibrary.selectedID = piece.id
            musicLibrary.open(piece, onOpen: { [weak self] url in
                guard let self, self.learner?.id == learnerID, self.canChatWithTutor else { return false }
                self.tutorChatPreservesConversation = true
                defer { self.tutorChatPreservesConversation = false }
                let opened = self.openCatalogPiece(url, piece: piece, tutored: false)
                self.tutorChat.observe(opened ? "Opened \(piece.title) in Practice." : "\(piece.title) could not be opened. Your practice piece was kept.")
                self.saveTutorChat()
                return opened
            }, onFailure: { [weak self] in
                guard let self, self.learner?.id == learnerID, self.canChatWithTutor else { return }
                self.tutorChat.observe("\(piece.title) could not be downloaded. Your practice piece was kept.")
                self.saveTutorChat()
            })
            return ("Opening \(piece.title) by \(piece.composer) from the Music Library…", true)
        case .goalSong(let song):
            guard let url = Self.bundledResource("Lessons/unit1/" + Block.SongChallenge.goalSongPath(song.id)) else {
                return ("\(song.title) isn't available in this build. Nothing was opened.", false)
            }
            showPracticeNow()
            guard loadReference(url, remember: false, title: song.title) else { return ("\(song.title) could not be opened.", false) }
        case .passage(let p):
            showPracticeNow()
            selectPassage(p.id)
            guard passage?.id == p.id else { return ("\(p.title) could not be opened.", false) }
        case .saved(let piece):
            let url = piece.folder.appendingPathComponent("piece.mid")
            showPracticeNow()
            if !bookImport.restoreSavedPiece(at: url) { loadReference(url, remember: false, title: piece.title) }
        case .recent(var piece):
            guard let url = resolveRecent(&piece) else { return ("\(item.title) can no longer be found. Nothing was opened.", false) }
            showPracticeNow()
            guard loadReference(url, title: piece.title) else { return ("\(item.title) could not be opened.", false) }
        }
        guard scoreID != before else { return ("\(item.title) could not be opened. Your practice piece was kept.", false) }
        return ("Opened \(item.title) in Practice.", true)
    }

    func tutorChatPreviewPiece(_ action: TutorChatAction) -> (outcome: String, ran: Bool) {
        guard let item = tutorChatFoundItem(action.pieceRef) else { return (Self.tutorUnknownPiece, false) }
        guard case .catalog(let piece) = item.source else {
            return ("Only Music Library pieces have a preview. I can open \(item.title) in Practice instead.", false)
        }
        if musicLibrary.previewingID == piece.id { return ("\(piece.title) is already playing in the Music Library.", true) }
        if tab != .musicLibrary {
            changingTabNow = true
            tab = .musicLibrary
            changingTabNow = false
            tabChanged()
        }
        if !musicLibrary.filtered.contains(piece) {
            musicLibrary.query = ""; musicLibrary.composer = nil; musicLibrary.difficulty = nil; musicLibrary.downloadedOnly = false
        }
        musicLibrary.selectedID = piece.id
        musicLibrary.preview(piece, play: { [weak self] url, finished in
            self?.previewCatalogPiece(url, onFinish: finished) ?? false
        }, stop: { [weak self] in self?.preview.stop() })
        return ("Previewing \(piece.title) by \(piece.composer) in the Music Library. Stop preview ends it.", true)
    }

    /// A page of the book in the Books tab: the open piece's book, or the one open there.
    func tutorChatOpenBookPage(_ action: TutorChatAction) -> (outcome: String, ran: Bool) {
        let url: URL? = tab == .books ? bookImport.documentURL ?? tutorChatBook()?.document.documentURL
            : tutorChatBook()?.document.documentURL ?? bookImport.documentURL
        guard let url, let document = PDFDocument(url: url) else { return ("No book is open. Open one in Books first.", false) }
        guard let page = action.page, (1...max(1, document.pageCount)).contains(page), document.pageCount > 0 else {
            return ("That book has pages 1–\(document.pageCount). No page was opened.", false)
        }
        guard bookImport.phase != .reading else { return ("Books is reading music from a page. Let it finish first.", false) }
        if tab != .books {
            changingTabNow = true
            tab = .books
            changingTabNow = false
            tabChanged()
        }
        if bookImport.documentURL?.standardizedFileURL == url.standardizedFileURL {
            bookImport.show(page: page - 1)
        } else {
            bookImport.open(url, page: page - 1)
        }
        return ("Showing page \(page) of \(url.deletingPathExtension().lastPathComponent) in Books.", true)
    }

    /// Practice, now: tab teardown runs before the new piece loads (see `openCatalogPiece`).
    private func showPracticeNow() {
        guard tab != .practice else { return }
        changingTabNow = true
        tab = .practice
        changingTabNow = false
        tabChanged()
    }

    // MARK: Context

    /// Levels in the library, the learner's own music, and what's selected in the Music Library.
    func tutorChatLibraryText() -> String {
        let pieces = musicLibrary.pieces
        var lines: [String] = []
        if !pieces.isEmpty {
            let counts = CatalogPiece.Difficulty.allCases.map { level in "\(level.rawValue) \(pieces.filter { $0.difficulty == level }.count)" }
            lines.append("Music Library: \(pieces.count) pieces (\(counts.joined(separator: ", "))).")
        }
        let skills = learnerSkills()
        lines.append("Suggested level for this learner: \(Self.tutorSuggestedLevel(skills).rawValue) (pieces passed: \(skills.passedTitles.count), hands together: \(skills.playedHandsTogether ? "yes" : "not yet"), fastest passed tempo: \(skills.fastestTempo.map { "\(Int($0)) BPM" } ?? "none")).")
        if let title = score?.title, let open = pieces.first(where: { $0.title == title }) {
            lines.append("Open piece's level: \(open.difficulty.rawValue) (\(open.title), \(open.composer)).")
        }
        let recent = learnerSettings.recentPieces.prefix(5).map(Self.tutorRecentTitle)
        if !recent.isEmpty { lines.append("Recent pieces: " + recent.joined(separator: "; ") + ".") }
        if let song = GoalSongs.song(learnerSettings.goalSong) { lines.append("Goal song: \(song.title) (Elementary).") }
        if let passages = book?.annotations.passages, !passages.isEmpty {
            lines.append("Open book \(book?.annotations.title ?? ""): \(passages.count) passages.")
        }
        if tab == .musicLibrary {
            let filters = [musicLibrary.query.isEmpty ? nil : "search “\(musicLibrary.query.prefix(100))”", musicLibrary.composer,
                           musicLibrary.difficulty?.rawValue, musicLibrary.downloadedOnly ? "downloaded only" : nil].compactMap { $0 }
            lines.append("Music Library tab filters: \(filters.isEmpty ? "none" : filters.joined(separator: ", ")); \(musicLibrary.filtered.count) pieces shown.")
            if let selected = musicLibrary.selected {
                lines.append("Selected: \(selected.title), \(selected.composer), \(selected.difficulty.rawValue)\(selected.keySignatureDescription.map { ", \($0)" } ?? "").")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
