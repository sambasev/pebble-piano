#if os(macOS)
import Foundation
import PianoLessons
import PianoPadState
import SwiftUI

/// How far a saved piece has got: read from the book, being learned, or passed. Shown in
/// Books (the library, the page's lines, the pieces list) so it's clear what's been done.
enum PieceStatus: Int, Comparable {
    case read, learning, passed

    static func < (a: PieceStatus, b: PieceStatus) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .read: return "Read"
        case .learning: return "Learning"
        case .passed: return "Passed"
        }
    }
    var color: Color {
        switch self {
        case .read: return Color.pp(0x1D5FA8, 0x7FB8FF)
        case .learning: return PP.warning
        case .passed: return PP.success
        }
    }
    var icon: String {
        switch self {
        case .read: return "doc.text.magnifyingglass"
        case .learning: return "figure.walk"
        case .passed: return "star.fill"
        }
    }
}

extension BookImportModel {
    /// Read, learning (a tutor lesson or a Learn page under way) or passed (the tutor's Perform,
    /// or the Learn page completed), for the learner now playing.
    func status(_ piece: SavedPiece) -> PieceStatus {
        let learnerID = session?.learner?.id
        let tutor = PieceLessonStore.progress(piece.id, learner: learnerID?.uuidString ?? "default")
        let page = learnerID.flatMap { id in
            session?.learnerStore.history(for: id).lessonProgress(unit: PieceLessonBuilder.unitID, page: "piece-\(piece.id)")
        }
        if tutor?.mastered == true || page?.isCompleted == true { return .passed }
        if let tutor, !tutor.completedSteps.isEmpty || (tutor.stepIndex ?? 1) > 0 { return .learning }
        if (page?.currentBlock ?? 0) > 0 { return .learning }
        return .read
    }

    /// Saved pieces from this book.
    func pieces(in book: URL) -> [SavedPiece] {
        pieces.filter { $0.book == book.lastPathComponent }
    }

    /// The furthest any piece from this book has got (nil when none has been read).
    func status(ofBook book: URL) -> PieceStatus? {
        pieces(in: book).map(status).max()
    }

    /// The book has been opened here before (its pages were scanned for lines of music).
    func wasOpened(_ book: URL) -> Bool {
        FileManager.default.fileExists(atPath: BookLibrary.cacheFolder(for: book).path)
    }

    /// The saved piece that line `index` of the page on screen belongs to.
    func savedPiece(onLine index: Int) -> SavedPiece? {
        guard let book = documentURL?.lastPathComponent else { return nil }
        return pieces.first { $0.book == book && $0.page == pageIndex && ($0.firstLine...$0.lastLine).contains(index) }
    }

    /// Pages of the open book with a saved piece on them (from 0).
    var pagesWithPieces: Set<Int> {
        guard let book = documentURL else { return [] }
        return Set(pieces(in: book).map(\.page))
    }
}

/// A small coloured capsule: the status, with its icon.
struct PieceStatusTag: View {
    let status: PieceStatus
    var text: String? = nil

    var body: some View {
        Label(text ?? status.label, systemImage: status.icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(status.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(status.color.opacity(0.16)))
            .fixedSize()
    }
}
#endif
