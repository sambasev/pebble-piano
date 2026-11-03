#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// C5: app help, input diagnostics and offered settings changes, from the tutor chat.
private final class HelpChat: TutorChatClient, @unchecked Sendable {
    var replies: [TutorChatReply] = []
    var calls: [(TutorChatContext, String)] = []
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((context, question))
        return replies.isEmpty ? TutorChatReply(onTopic: true, reply: "Let's check your input.") : replies.removeFirst()
    }
}

final class TutorChatHelpTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatHelp") }
    override func tearDown() { sandbox.remove() }

    @MainActor private func player() throws -> PlaySession {
        let session = sandbox.session()
        session.addLearner(name: "Adult", kind: .adult)
        let notes = [60, 62, 64, 65, 67, 69, 71, 72].enumerated().map { i, pitch in
            NoteEvent(pitch: pitch, onset: Double(i) * 2, offset: Double(i) * 2 + 0.5,
                      onsetBeats: Double(i) * 4, offsetBeats: Double(i) * 4 + 1)
        }
        let file = sandbox.folder.appendingPathComponent("Eight bars.mid")
        try MIDIFile.write(notes: notes).write(to: file)
        XCTAssertTrue(session.loadReference(file))
        session.setModeNow(.wait)
        session.tutorChatClient = HelpChat()
        session.makeTutorFeedbackClient = { throw ModelError.missingKey(.meta) }
        return session
    }

    @MainActor private func settle(_ session: PlaySession) async {
        for _ in 0..<300 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if !session.tutorChatBusy { return }
        }
        XCTFail("Tutor did not settle")
    }

    @MainActor func testGuideAndDiagnosticsGoOnlyWithAppQuestions() throws {
        let session = try player()
        let help = session.tutorChatContext(for: "It can't hear my piano")
        XCTAssertTrue(help.appGuide.contains("Calibrate piano (mic)"))
        XCTAssertTrue(help.diagnostics.contains("Chosen input:"))
        XCTAssertTrue(help.diagnostics.contains("Bluetooth MIDI connected: none."))
        XCTAssertTrue(help.prompt.contains("Input diagnostics:"))
        let music = session.tutorChatContext(for: "What is a dotted half note?")
        XCTAssertEqual(music.appGuide, "")
        XCTAssertEqual(music.diagnostics, "")
    }

    @MainActor func testAFewNotesHeardTakeBringsDiagnosticsAlong() throws {
        let session = try player()
        session.mouseDown(on: 60); session.mouseUp(); session.finishTake() // 1 of 8 notes heard
        XCTAssertTrue(session.tutorChatFewNotesDetected)
        XCTAssertTrue(session.tutorChatContext(for: "What should I do next?").diagnostics.contains("of 8 expected notes heard"))
    }

    @MainActor func testOfferedChangesWaitForTheLearnersTap() async throws {
        let session = try player()
        let before = session.chosenInput
        let fake = HelpChat()
        fake.replies = [.init(onTopic: true, reply: "Try the computer keyboard.", actions: [
            .init(kind: .switchInput, input: "computerKeyboard"), .init(kind: .practicePassage, fromBar: 4, toBar: 4),
        ])]
        session.tutorChatClient = fake
        session.sendTutorChat("My mic isn't working, can I use the keyboard?")
        await settle(session)
        XCTAssertEqual(session.tutorChatConfirmation?.label, "Use the computer keyboard")
        XCTAssertEqual(session.chosenInput, before, "nothing changes before the tap")
        XCTAssertNil(session.tutor, "a help action ends the plan")
        session.confirmTutorChatOffer()
        XCTAssertEqual(session.chosenInput, .computerKeyboard)
        XCTAssertNil(session.tutorChatConfirmation)
        XCTAssertEqual(session.tutorChat.turns.last?.text, "Done: Use the computer keyboard.")

        _ = session.applyTutorChatAction(.init(kind: .openSettings, section: "practice"))
        session.declineTutorChatOffer()
        XCTAssertNil(session.tutorChatOpenPanel)
        _ = session.applyTutorChatAction(.init(kind: .openSettings, section: "practice"))
        session.confirmTutorChatOffer()
        XCTAssertEqual(session.tutorChatOpenPanel, .practice)
    }

    @MainActor func testInvalidHelpActionsAreRefused() throws {
        let session = try player()
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .switchInput, input: "usb")).contains("Nothing changed"))
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .switchInput, input: "midi")).contains("No Bluetooth MIDI piano"))
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .openSettings, section: "secret")).contains("Nothing changed"))
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .markPlayedRight)).contains("no graded take"))
        XCTAssertNil(session.tutorChatConfirmation)
    }

    @MainActor func testPlayedRightKeepsTheTakeAndTheGrade() throws {
        let session = try player()
        session.mouseDown(on: 61); session.mouseUp(); session.finishTake()
        let score = session.report?.notes.score
        let outcome = session.applyTutorChatAction(.init(kind: .markPlayedRight))
        XCTAssertTrue(outcome.contains("grade is unchanged"), outcome)
        let folder = BookLibrary.support.appendingPathComponent("PlayedRight")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(Set(files.map { ($0 as NSString).pathExtension }), ["mid", "json"])
        XCTAssertTrue(files.contains { $0.hasSuffix(".label.json") })
        XCTAssertEqual(session.report?.notes.score, score)
    }
}
#endif
