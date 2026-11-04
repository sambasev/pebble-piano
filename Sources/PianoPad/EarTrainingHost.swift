#if os(macOS)
import AppKit
import SwiftUI
import EarTrainingUI
import EarTrainingIntegration
import PianoGraderCore
import PianoPadState

/// A lease prevents a late Stop from a disappearing view affecting a new tab's audio.
@MainActor final class AppEarSequenceOutput: EarSequenceOutput {
    private let startBody: ([NoteEvent]) -> UUID?
    private let positionBody: (UUID) -> Double?
    private let stopBody: (UUID) -> Void
    private var lease: UUID?
    init(start: @escaping ([NoteEvent]) -> UUID?, position: @escaping (UUID) -> Double?, stop: @escaping (UUID) -> Void) {
        startBody = start; positionBody = position; stopBody = stop
    }
    func start(_ notes: [NoteEvent]) -> Bool {
        stop()
        lease = startBody(notes)
        return lease != nil
    }
    var position: Double? { lease.flatMap(positionBody) }
    func stop() {
        if let lease { stopBody(lease) }
        lease = nil
    }
}

extension EarButtonStyles {
    /// Ear-training lessons inside the app use the app's pills.
    static let pebblePiano = EarButtonStyles(
        primary: { AnyView($0.buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))) },
        secondary: { AnyView($0.buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))) }
    )
}

/// Shared daily statistics are shown by both kinds of session summary.
struct PracticeDayStatistics: View {
    let sessions: [PracticeSession]
    var body: some View {
        let minutes = sessions.reduce(0) { $0 + $1.minutes }
        let quizzes = sessions.flatMap(\.earQuizzes).count
        let pages = sessions.reduce(0) { $0 + $1.completedPages.count }
        VStack(spacing: 4) {
            Text("Today: \(minutes) min · \(pages) lesson \(pages == 1 ? "page" : "pages") · \(quizzes) ear \(quizzes == 1 ? "quiz" : "quizzes")")
                .font(.ppCallout).foregroundColor(PP.inkMuted)
            let results = sessions.flatMap(\.earQuizzes)
            let total = results.reduce(0) { $0 + $1.total }
            if total > 0 {
                Text("Ear training: \(results.reduce(0) { $0 + $1.correct })/\(total) correct")
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }
        }
    }
}

#endif
