#if os(macOS)
import PianoLessons
import PianoPadState
import SwiftUI

extension Sticker {
    var swiftUIColor: Color {
        switch color {
        case "success": return PP.success
        case "apricot": return PP.apricot
        case "lilac": return PP.lilac
        case "mistake": return PP.mistake
        default: return PP.accent
        }
    }
}

/// A round sticker: its symbol on a coloured disc with a white rim.
struct StickerView: View {
    let sticker: Sticker
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(sticker.swiftUIColor)
            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(2, size * 0.06))
            Image(systemName: sticker.symbol)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.03)
        .accessibilityLabel("\(sticker.name) sticker")
    }
}

/// For a child learner's grown-up: this week, notes learned, where they're stuck, one tip,
/// and the teacher choice (kept out of the child's way).
struct GrownUpsView: View {
    @ObservedObject var runner: LessonRunner
    @Environment(\.dismiss) private var dismiss
    @State private var report: LessonRunner.GrownUpsReport?

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("For grown-ups").ppEyebrow()
            if let r = report {
                Text("How \(r.name) is getting on").font(.ppTitle)
                HStack(spacing: PP.Space.s4) {
                    stat("\(r.minutesThisWeek)", "minutes this week")
                    stat("\(r.daysThisWeek)", r.daysThisWeek == 1 ? "day this week" : "days this week")
                    stat("\(r.pagesDone) of \(r.pageCount)", "pages done")
                }
                row("music.note", "Notes learned",
                    r.notesLearned.isEmpty ? "None yet: the first page teaches Middle C." : r.notesLearned.joined(separator: ", "))
                row("ear", "Ear training", "\(r.earQuizzesThisWeek) \(r.earQuizzesThisWeek == 1 ? "quiz" : "quizzes") this week. Listening practice counts toward the minutes and days above.")
                row("exclamationmark.bubble", "Stuck on",
                    r.stuckPage.map { "\($0.title)" + (r.stuckDetail.map { ": \($0.lowercased())" } ?? "") } ?? "Nothing right now.")
                row("lightbulb", "Tip", r.tip)
                Divider()
                VStack(alignment: .leading, spacing: PP.Space.s2) {
                    Text("Teacher").ppEyebrow()
                    Picker("Teacher", selection: Binding(get: { runner.persona.id }, set: { runner.setPersona($0) })) {
                        ForEach(Persona.builtIn, id: \.id) { p in
                            Text("\(p.name): \(p.summary)").tag(p.id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text("Alex suits most children. Kriti, the strict teacher, isn't shown to children; choose her here if you'd like.")
                        .font(.ppCaption).foregroundColor(PP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PP.Space.s6)
        .frame(width: 520)
        .onAppear { report = runner.grownUpsReport() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.ppTitle).monospacedDigit()
            Text(label).font(.ppCaption).foregroundColor(PP.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppGlass(cornerRadius: PP.Radius.md, padding: PP.Space.s3)
    }

    private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: PP.Space.s3) {
            Image(systemName: symbol).foregroundColor(PP.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ppHeadline)
                Text(text).font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
