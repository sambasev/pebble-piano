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
            if !compact && !session.tutorChatGoal.isEmpty {
                Text("Goal: " + session.tutorChatGoal)
                    .font(.caption).foregroundColor(PP.inkMuted).lineLimit(2)
            }
            // The conversation scrolls on its own, newest at the bottom; the question box stays put.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PP.Space.s3) {
                        if session.tutorChat.turns.isEmpty {
                            Text("I can read the open score and your recent practice results. Tell me your goal, or ask me to teach a passage—for example, ‘Help me learn bar 4 slowly.’")
                                .font(.callout).foregroundColor(PP.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(session.tutorChat.turns) { turn in
                            bubble(turn).id(turn.id)
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
            }
            if !session.tutorChatQueuedActions.isEmpty {
                Text("Then: " + session.tutorChatQueuedActions.map(\.summary).joined(separator: " · "))
                    .font(.caption).foregroundColor(PP.inkMuted).lineLimit(2)
                    .accessibilityLabel("Next in the tutor's plan: " + session.tutorChatQueuedActions.map(\.summary).joined(separator: ", then "))
            }
            if !session.tutorChatBusy && !session.tutorChat.suggestions.isEmpty {
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
            if session.tutorChatBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Your tutor is thinking…").font(.caption).foregroundColor(PP.inkMuted)
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
            if let book = session.tutorChatBookLabel {
                Toggle(isOn: $session.tutorChatUsesBook) { Text("Use \(book)").font(.caption) }
                    .help("Send the book page's text and a picture of it with each question")
            }
        }
    }

    private func send() {
        guard !session.tutorChatBusy, TutorChat.clean(draft) != nil else { return }
        session.sendTutorChat(draft)
        draft = ""
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
