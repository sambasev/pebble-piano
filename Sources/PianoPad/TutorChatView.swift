#if os(macOS)
import SwiftUI
import PianoLessons

/// Ask your tutor: a music-only chat in the tutor panel. Shown for adults only (`TutorPanel`).
struct TutorChatView: View {
    @EnvironmentObject var session: PlaySession
    @Environment(\.ppCompact) private var compact
    @State private var draft = ""
    @State private var focused = false
    @State private var composerHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            if !compact && !session.tutorChatIsChild && !session.tutorChatGoal.isEmpty {
                Text("Goal: " + session.tutorChatGoal)
                    .font(.caption).foregroundColor(PP.inkMuted).lineLimit(2)
            }
            if let plan = session.tutorChatSessionPlan { planCard(plan) }
            // The conversation scrolls on its own, newest at the bottom; the question box stays put.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PP.Space.s3) {
                        if session.tutorChat.turns.isEmpty && session.tutorChatIsChild {
                            Text("Tap a button and I'll help you play!")
                                .font(.title3).foregroundColor(PP.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if session.tutorChat.turns.isEmpty {
                            Text("I can read the open score and your recent practice results. Tell me your goal, or ask me to teach a passage—for example, ‘Help me learn bar 4 slowly.’")
                                .font(.callout).foregroundColor(PP.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(session.tutorChat.turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                        if session.tutorChatBusy, let text = session.tutorChatStreamingText {
                            bubble(TutorChatTurn(role: .tutor, text: text)).id("streaming")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PP.Space.s2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    if let last = session.tutorChat.turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: session.tutorChat.turns.last?.id) { last in
                    guard let last else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: session.tutorChatStreamingText) { text in
                    if text != nil { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }
            if !session.tutorChatQueuedActions.isEmpty {
                Text("Then: " + session.tutorChatQueuedActions.map(\.summary).joined(separator: " · "))
                    .font(.caption).foregroundColor(PP.inkMuted).lineLimit(2)
                    .accessibilityLabel("Next in the tutor's plan: " + session.tutorChatQueuedActions.map(\.summary).joined(separator: ", then "))
            }
            if !session.tutorChatIsChild && !session.tutorChatBusy && !session.tutorChat.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: PP.Space.s1) {
                    ForEach(session.tutorChat.suggestions, id: \.self) { suggestion in
                        Button { session.sendTutorChat(suggestion) } label: {
                            Text(suggestion).lineLimit(1).truncationMode(.tail)
                        }
                        .buttonStyle(PPGlassButtonStyle(height: 26))
                        .help("Ask: \(suggestion)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let offer = session.tutorChatConfirmation, !session.tutorChatBusy {
                HStack(spacing: PP.Space.s2) {
                    Button(offer.label) { session.confirmTutorChatOffer() }
                        .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                        .help("Your tutor suggested this; nothing changes until you press it")
                    Button("Not now") { session.declineTutorChatOffer() }
                        .buttonStyle(PPGlassButtonStyle())
                }
            }
            if session.tutorChatBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(session.tutorChatStreamingText == nil ? "Your tutor is thinking…" : "Your tutor is answering…")
                        .font(.caption).foregroundColor(PP.inkMuted)
                    Spacer()
                    Button("Stop") { session.stopTutorChat() }
                }
            }
            if let note = session.tutorChatNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if session.tutorChatAwaitingStart {
                Button { session.startPreparedTutorChatExercise() } label: {
                    Label("Start practice", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                .disabled(session.tutorChatBusy)
                .help("Start the count-in when you're ready to play")
            }
            if session.tutorChatOffersGrade && session.phase == .recording {
                Button("Grade take") { session.finishTutorChatTake() }
                    .buttonStyle(PPGlassButtonStyle())
            }
            if session.tutorChatIsChild {
                childButtons
            } else {
            HStack(alignment: .bottom, spacing: PP.Space.s2) {
                TutorChatComposer(text: $draft, focused: $focused, height: $composerHeight,
                                  send: send)
                    .frame(height: composerHeight)
                Button {
                    if session.tutorChatCoaching { session.pauseTutorChatCoaching() }
                    else { session.tutorChatCoaching = true }
                } label: { Image(systemName: session.tutorChatCoaching ? "pause.fill" : "sparkles") }
                .buttonStyle(PPIconButtonStyle(kind: .mode, isOn: session.tutorChatCoaching))
                .accessibilityLabel("Coach after each take")
                .accessibilityValue(session.tutorChatCoaching ? "On" : "Off")
                .help(session.tutorChatCoaching ? "Pause automatic coaching" : "Let the tutor review each graded take and choose the next step")
                .padding(.bottom, 1)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(PPIconButtonStyle(kind: .mode, isOn: true))
                .disabled(TutorChat.clean(draft) == nil || session.tutorChatBusy)
                .accessibilityLabel("Send question")
                .help("Send question (Return). Shift-Return adds a new line.")
                .padding(.bottom, 1)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: PP.Radius.sm).fill(PP.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.sm)
                .strokeBorder(focused ? PP.focusRing : PP.inkStaff.opacity(0.45), lineWidth: focused ? 2 : 1)
                .allowsHitTesting(false))
            }
            if !session.tutorChatIsChild, let book = session.tutorChatBookLabel {
                Toggle(isOn: $session.tutorChatUsesBook) { Text("Use \(book)").font(.caption) }
                    .help("Send the book page's text and a picture of it with each question")
            }
        }
    }

    /// A child taps one of a few fixed questions; there is no text box (C6).
    private var childButtons: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            ForEach(TutorChildPrompts.chips.filter { $0 != TutorChildPrompts.grownUps }, id: \.self) { chip in
                Button(chip) { session.askTutorAsChild(chip) }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .disabled(session.tutorChatBusy)
            }
            Button(TutorChildPrompts.grownUps) { session.askTutorAsChild(TutorChildPrompts.grownUps) }
                .buttonStyle(PPGlassButtonStyle(height: 26))
                .disabled(session.tutorChatBusy)
                .help("For a parent: time practised, what's going well and where they're stuck")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func send() {
        guard !session.tutorChatBusy, TutorChat.clean(draft) != nil else { return }
        session.sendTutorChat(draft)
        draft = ""
    }

    /// Today's plan from the tutor: tick steps off; the tutor sees what's done.
    private func planCard(_ plan: TutorSessionPlan) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s1) {
            HStack {
                Text("Today's plan · \(plan.minutes) min").font(.caption.weight(.semibold)).foregroundColor(PP.ink)
                Spacer()
                Button { session.setTutorChatSessionPlan(nil) } label: { Image(systemName: "xmark") }
                    .buttonStyle(PPIconButtonStyle(size: 22))
                    .accessibilityLabel("Clear today's plan")
                    .help("Clear today's plan")
            }
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                Toggle(isOn: Binding(get: { step.done }, set: { _ in session.toggleTutorChatPlanStep(index) })) {
                    Text(step.text).font(.caption).foregroundColor(step.done ? PP.inkMuted : PP.ink)
                        .strikethrough(step.done).fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(PPCheckboxToggleStyle())
            }
        }
        .padding(PP.Space.s2)
        .background(RoundedRectangle(cornerRadius: PP.Radius.sm).fill(PP.surfaceRaised))
    }

    @ViewBuilder private func bubble(_ turn: TutorChatTurn) -> some View {
        if turn.role == .app {
            Text(turn.text).font(.caption).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let mine = turn.role == .learner
            HStack {
                if mine { Spacer(minLength: 24) }
                Text(turn.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .foregroundColor(turn.refused && !mine ? PP.inkMuted : PP.ink)
                    .padding(.horizontal, PP.Space.s3).padding(.vertical, PP.Space.s2)
                    .background(RoundedRectangle(cornerRadius: PP.Radius.sm)
                        .fill(mine ? PP.accent.opacity(0.16) : PP.surfaceRaised))
                if !mine { Spacer(minLength: 24) }
            }
        }
    }
}

extension PlaySession {
    /// "page 12 of Learning the Code", when the open piece came from a book.
    var tutorChatBookLabel: String? {
        if let book, let passage { return "page \(passage.page) of \(book.annotations.title)" }
        guard let piece = tutorChatSavedPiece else { return nil }
        return "page \(piece.page + 1) of \((piece.book as NSString).deletingPathExtension)"
    }
}
#endif
