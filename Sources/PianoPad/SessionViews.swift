#if os(macOS)
import PianoLessons
import PianoPadState
import SwiftUI
import EarTrainingIntegration

private enum PracticeSummaryPresentation: Identifiable {
    case lesson(LessonRunner.SessionSummary)
    case ear(PracticeSession)
    var id: UUID {
        switch self { case .lesson(let value): return value.id; case .ear(let value): return value.id }
    }
}

/// Puts the session summary sheet on whatever the window shows (it can appear after leaving
/// the Learn tab).
struct SessionSummaryHost: ViewModifier {
    @ObservedObject var runner: LessonRunner
    @ObservedObject var ear: EarPracticeCoordinator

    func body(content: Content) -> some View {
        content.sheet(item: Binding<PracticeSummaryPresentation?>(
            get: { runner.sessionSummary.map(PracticeSummaryPresentation.lesson) ?? ear.summary.map(PracticeSummaryPresentation.ear) },
            set: { value in if value == nil { runner.sessionSummary = nil; ear.summary = nil } }
        )) { summary in
            switch summary {
            case .lesson(let summary): SessionSummaryView(runner: runner, summary: summary)
            case .ear(let summary): EarPracticeSummaryView(coordinator: ear, session: summary)
            }
        }
    }
}

/// "Today: C, D, E · 2 pages · 12 min", the weekly streak, and what's next.
struct SessionSummaryView: View {
    @ObservedObject var runner: LessonRunner
    let summary: LessonRunner.SessionSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: PP.Space.s4) {
            Text("Session done").ppEyebrow()
            Text(headline).font(.ppTitle).multilineTextAlignment(.center)
            Text(todayLine).font(.ppHeadline).foregroundColor(PP.inkMuted).multilineTextAlignment(.center)
            PracticeDayStatistics(sessions: runner.todaySessions)
            if summary.session.stars > 0 {
                Label("\(summary.session.stars) star\(summary.session.stars == 1 ? "" : "s") earned", systemImage: "star.fill")
                    .font(.ppCallout)
            }
            Label(WeeklyStreak.label(days: summary.streakDays), systemImage: "flame.fill")
                .font(.ppCallout)
                .foregroundColor(PP.accent)
                .help("Days you practised this week. Missing a day costs nothing.")
            if let next = summary.nextPage {
                VStack(spacing: 2) {
                    Text("Next up").ppEyebrow()
                    Text(next.title).font(.ppHeadline)
                }
                .padding(.top, PP.Space.s2)
            }
            HStack(spacing: PP.Space.s3) {
                Button("Done") { dismiss() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .keyboardShortcut(.cancelAction)
                if let next = summary.nextPage {
                    Button("Keep going") { runner.keepGoing(with: next.id) }
                        .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, PP.Space.s2)
        }
        .padding(PP.Space.s8)
        .frame(minWidth: 420)
    }

    private var headline: String {
        let s = summary.session
        if !s.notesLearned.isEmpty { return "You learned \(Self.list(s.notesLearned))!" }
        if !s.completedPages.isEmpty { return "Nice work today!" }
        return "Good practice."
    }

    /// "Today: C, D, E · 2 pages · 12 min"
    private var todayLine: String {
        let s = summary.session
        var parts: [String] = []
        if !s.notesLearned.isEmpty { parts.append(s.notesLearned.joined(separator: ", ")) }
        let pages = s.completedPages.isEmpty ? s.pages.count : s.completedPages.count
        if pages > 0 {
            parts.append(s.completedPages.isEmpty ? "\(pages) page\(pages == 1 ? "" : "s") played"
                                                  : "\(pages) page\(pages == 1 ? "" : "s") done")
        }
        parts.append("\(s.minutes) min")
        return "This session: " + parts.joined(separator: " · ")
    }

    /// "C", "C and D", "C, D and E"
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}

/// On the unit page when coming back: the warm-up offer, then how it went.
struct WarmUpCard: View {
    @ObservedObject var runner: LessonRunner
    let warmUp: LessonRunner.WarmUp

    var body: some View {
        HStack(alignment: .center, spacing: PP.Space.s4) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(PP.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.ppHeadline)
                Text(detail).font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            buttons
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s4)
    }

    private var icon: String {
        if case .done = warmUp.phase { return warmUp.suggestsReview ? "arrow.uturn.backward.circle" : "checkmark.circle" }
        return "sun.max"
    }

    private var title: String {
        switch warmUp.phase {
        case .offered, .running: return "Welcome back! Warm up first?"
        case .done(let notes):
            if runner.isChild { return "Warm-up done!" }
            return "Warm-up: notes \(Int((notes * 100).rounded()))% (last time \(Int((warmUp.block.notes * 100).rounded()))%)"
        }
    }

    private var detail: String {
        switch warmUp.phase {
        case .offered, .running:
            return "About a minute: play along with the last timed step you did, on \(warmUp.pageTitle)."
        case .done:
            return warmUp.suggestsReview
                ? "That's a fair bit down on last time. A quick look back at \(warmUp.pageTitle) will help."
                : "Nicely warmed up. On to the next page."
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch warmUp.phase {
        case .offered, .running:
            Button("Not now") { runner.dismissWarmUp() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            Button("Warm up") { runner.startWarmUp() }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
        case .done:
            if warmUp.suggestsReview {
                Button("Continue") { runner.continueAfterWarmUp() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                Button("Review \(warmUp.pageTitle)") { runner.reviewWarmUpPage() }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
            } else {
                Button("Close") { runner.dismissWarmUp() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                // Warmed up fine: on to the coach's page by itself. A big drop stays a choice.
                TimedContinueButton(title: "Continue", seconds: AutoAdvance.seconds(.warmUpDone, child: runner.isChild)) {
                    runner.continueAfterWarmUp()
                }
                .id("warmup-done")
            }
        }
    }
}
#endif
