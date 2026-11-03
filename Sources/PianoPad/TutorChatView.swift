#if os(macOS)
import SwiftUI
import PianoLessons

/// Ask your tutor: a music-only chat in the tutor panel. Shown for adults only (`TutorPanel`).
struct TutorChatView: View {
    @EnvironmentObject var session: PlaySession
    @State private var draft = ""
    @State private var focused = false
    @State private var composerHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            // The conversation scrolls on its own, newest at the bottom; the question box stays put.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PP.Space.s3) {
                        if session.tutorChat.turns.isEmpty {
                            Text("Ask about this piece, the book page, technique, theory or anything else about music.")
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
            HStack(alignment: .bottom, spacing: PP.Space.s2) {
                TutorChatComposer(text: $draft, focused: $focused, height: $composerHeight,
                                  send: send)
                    .frame(height: composerHeight)
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

extension PlaySession {
    /// "page 12 of Learning the Code", when the open piece came from a book.
    var tutorChatBookLabel: String? {
        if let book, let passage { return "page \(passage.page) of \(book.annotations.title)" }
        guard let piece = tutorChatSavedPiece else { return nil }
        return "page \(piece.page + 1) of \((piece.book as NSString).deletingPathExtension)"
    }
}
#endif
