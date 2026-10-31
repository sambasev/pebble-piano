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

@MainActor struct EarTrainingHost: View {
    @ObservedObject var coordinator: EarPracticeCoordinator
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var appearance: EarTrainingAppearance {
        EarTrainingAppearance(accent: PP.accent, ink: PP.ink, cardSurface: PP.surfaceGlass,
                              background: .clear, displayFont: .ppTitle, titleFont: .ppHeadline, embedded: true)
    }
    var body: some View {
        VStack(spacing: 0) {
            if let error = coordinator.historyError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Button("Retry saving") { coordinator.retryHistory() }
                }.font(.ppCallout).foregroundColor(PP.warning).padding(PP.Space.s3)
            }
            EarTrainingView(session: coordinator.session, appearance: appearance)
                .id(coordinator.sessionIdentity)
        }
        .onReceive(timer) { _ in coordinator.tick() }
    }
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

@MainActor struct EarPracticeSummaryView: View {
    @ObservedObject var coordinator: EarPracticeCoordinator
    let session: PracticeSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: PP.Space.s4) {
            Text("Session done").ppEyebrow()
            Text("Good listening.").font(.ppTitle)
            Text("This session: \(session.minutes) min · \(session.earQuestionsAnswered) \(session.earQuestionsAnswered == 1 ? "answer" : "answers") · \(session.earQuizzes.count) \(session.earQuizzes.count == 1 ? "quiz" : "quizzes")")
                .font(.ppHeadline).foregroundColor(PP.inkMuted)
            PracticeDayStatistics(sessions: coordinator.today())
            Label(WeeklyStreak.label(days: coordinator.streakDays), systemImage: "flame.fill")
                .font(.ppCallout).foregroundColor(PP.accent)
            if let error = coordinator.historyError {
                Text(error).font(.ppCallout).foregroundColor(PP.warning)
                Button("Retry saving") { coordinator.retryHistory() }
            }
            HStack(spacing: PP.Space.s3) {
                Button("Done") { dismiss() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin)).keyboardShortcut(.cancelAction)
                Button("More ear training") {
                    coordinator.summary = nil
                    dismiss()
                    NotificationCenter.default.post(name: .openEarTraining, object: nil)
                }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin)).keyboardShortcut(.defaultAction)
            }
        }.padding(PP.Space.s8).frame(minWidth: 460)
    }
}

extension Notification.Name {
    static let openEarTraining = Notification.Name("PerfectPiano.openEarTraining")
}
#endif
