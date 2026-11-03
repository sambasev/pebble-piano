#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// The tutor's scenarios end to end, against the live model: a real session with real pieces,
/// takes played through the on-screen keyboard and graded by the real grader, the real
/// library, lessons and memory, the real Meta client, and the app's own action checks. Each
/// case passes on what the app did (an exercise started, a plan saved, a button offered),
/// not on the model's words alone.
///
/// Opt-in and billed: `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`.
/// Writes `docs/tutor_live_evaluation.md` and `.json`.
final class TutorLiveEvalTests: XCTestCase {
    struct Outcome: Codable {
        var id: String
        var scenario: String
        var description: String
        var passed: Bool
        var failures: [String]
        var seconds: Double
        var transcript: [String]
    }

    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("LiveEval") }
    override func tearDown() { sandbox.remove() }

    // MARK: Real setup

    @MainActor private func session(_ kind: Learner.Kind = .adult, piece: String? = "Examples/ode-to-joy-c.mid",
                                    client: ModelTutorChatClient) throws -> PlaySession {
        let session = sandbox.session()
        session.addLearner(name: kind == .adult ? "Sam" : "Kid", kind: kind)
        if let piece { XCTAssertTrue(session.loadReference(try XCTUnwrap(PlaySession.bundledResource(piece)))) }
        session.setModeNow(.wait)
        session.makeTutorChatClient = { client }
        return session
    }

    /// Plays the piece note by note on the on-screen keyboard, as a learner would: waits for
    /// the guide's next keys, hits a wrong key (a semitone up) first at each note index in
    /// `wrongAt`, and stops after `upTo` notes. Starts again first, like the button, when a
    /// take is already graded. The take is graded and saved as any take is.
    @MainActor private func play(_ session: PlaySession, wrongAt: Set<Int> = [], upTo: Int? = nil) async {
        if session.phase != .waiting { session.resetTake() }
        var index = 0
        while index < (upTo ?? 400) {
            for _ in 0..<40 where session.expected.isEmpty { try? await Task.sleep(nanoseconds: 5_000_000) }
            guard !session.expected.isEmpty else { break }
            let keys = session.expected.sorted()
            if wrongAt.contains(index), let first = keys.first {
                session.mouseDown(on: first + 1); session.mouseUp()
            }
            for key in keys { session.mouseDown(on: key); session.mouseUp() }
            index += 1
        }
        if session.phase == .recording { session.finishTake() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    @MainActor private func answer(_ session: PlaySession, timeout: Double = 60) async {
        let start = Date()
        while session.tutorChatBusy && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor private func until(_ timeout: Double, _ condition: () -> Bool) async {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < timeout { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    @MainActor private func ask(_ session: PlaySession, _ question: String) async -> String {
        session.sendTutorChat(question)
        await answer(session)
        return lastReply(session)
    }

    @MainActor private func lastReply(_ session: PlaySession) -> String {
        session.tutorChat.turns.last { $0.role == .tutor }?.text ?? ""
    }

    @MainActor private func appNotes(_ session: PlaySession) -> String {
        session.tutorChat.turns.filter { $0.role == .app }.map(\.text).joined(separator: "\n")
    }

    private static func has(_ text: String, _ any: [String]) -> Bool {
        any.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func day(_ offset: Int) -> (date: Date, text: String) {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return (date, f.string(from: date))
    }

    // MARK: The run

    @MainActor func testTutorScenariosAgainstTheLiveModel() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIANOAI_LIVE"] == "1", "set PIANOAI_LIVE=1 and MODEL_API_KEY to call Meta")
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["MODEL_API_KEY"], "MODEL_API_KEY")
        let client = ModelTutorChatClient(client: ModelClient(endpoint: .init(provider: .meta, baseURL: ModelProvider.meta.defaultBaseURL!, apiKey: key),
                                                              log: UsageLog(printsToConsole: false)),
                                          model: AISettings.shared.tutorModel)
        var outcomes: [Outcome] = []

        func run(_ id: String, _ scenario: String, _ description: String,
                 _ body: () async throws -> (PlaySession?, [String])) async {
            let start = Date()
            var failures: [String] = []
            var transcript: [String] = []
            do {
                let (session, fails) = try await body()
                failures = fails
                if let session {
                    transcript = session.tutorChat.turns.map { "\($0.role.rawValue): \($0.text)" }
                    if let note = session.tutorChatNote { failures.append("App note: \(note)") }
                    session.stopTutorChat(); session.endTutoring()
                }
            } catch {
                failures = ["Setup failed: \(error)"]
            }
            let outcome = Outcome(id: id, scenario: scenario, description: description, passed: failures.isEmpty,
                                  failures: failures, seconds: (Date().timeIntervalSince(start) * 10).rounded() / 10,
                                  transcript: transcript)
            print("\(outcome.passed ? "PASS" : "FAIL") \(id) (\(outcome.seconds)s)" + failures.map { "\n    - \($0)" }.joined())
            outcomes.append(outcome)
            sandbox.remove(); sandbox = AppDataSandbox("LiveEval")
        }

        // A · Understanding the music in front of me
        await run("a1_count_rhythm", "A", "Explains the rhythm of a real bar from the score data and offers follow-ups") {
            let s = try session(client: client)
            let reply = await ask(s, "How do I count the rhythm in bar 4?")
            var f: [String] = []
            if !Self.has(reply, ["beat", "count", "1"]) { f.append("Reply doesn't count beats: \(reply)") }
            if s.tutorChat.suggestions.isEmpty { f.append("No follow-up chips offered") }
            return (s, f)
        }
        await run("a2_tap_follow_up", "A", "A tapped follow-up chip is answered in the same conversation") {
            let s = try session(client: client)
            _ = await ask(s, "What notes are in bar 1?")
            guard let chip = s.tutorChat.suggestions.first else { return (s, ["No follow-up chips to tap"]) }
            s.sendTutorChat(chip); await answer(s)
            let refused = s.tutorChat.turns.last?.refused == true
            return (s, refused ? ["The tutor refused its own suggestion “\(chip)”"] : [])
        }

        // B · Practising the piece
        await run("b1_listen_then_try", "B", "“Play it, then let me try” runs a demonstration and queues the practice") {
            let s = try session(client: client)
            _ = await ask(s, "Play bars 1 to 2 for me first, then let me try them.")
            var f: [String] = []
            if !Self.has(appNotes(s), ["bars 1–2"]) { f.append("No demonstration of bars 1–2 started: \(appNotes(s))") }
            if s.tutorChatQueuedActions.first?.kind != .practicePassage { f.append("Practice wasn't queued after the demonstration: \(s.tutorChatQueuedActions.map(\.summary))") }
            return (s, f)
        }
        await run("b2_recurring_mistakes", "B", "After three real takes with the same slip, names the bar") {
            let s = try session(client: client)
            for _ in 0..<3 { await play(s, wrongAt: [5]) }
            let trouble = s.tutorChatContext(for: "x").trends
            let bar = trouble.range(of: #"bar (\d+), 3 of 3"#, options: .regularExpression).map { String(trouble[$0]).split(separator: " ")[1].dropLast() }
            let reply = await ask(s, "Where do I keep making mistakes?")
            guard let bar else { return (s, ["The grader didn't record a recurring bar: \(trouble)"]) }
            return (s, Self.has(reply, ["bar \(bar)", "bar  \(bar)", "measure \(bar)"]) ? [] : ["Reply doesn't name bar \(bar): \(reply)"])
        }
        await run("b3_not_ready_from_wait_mode", "B", "Doesn't call the piece ready from note-by-note takes") {
            let s = try session(client: client)
            for _ in 0..<3 { await play(s) }
            let reply = await ask(s, "I've played it perfectly three times now. Am I ready to play it at full speed?")
            let claims = Self.has(reply, ["you're ready", "you are ready", "mastered", "you've got it"])
            return (s, claims ? ["Claimed readiness from note-by-note takes: \(reply)"] : [])
        }
        await run("b4_plan_session", "B", "Plans a 15-minute session as a saved checklist") {
            let s = try session(client: client)
            await play(s, wrongAt: [5])
            _ = await ask(s, "Make me a 15 minute practice plan for today.")
            guard let plan = s.tutorChatSessionPlan else { return (s, ["No plan was saved: \(appNotes(s))"]) }
            return (s, plan.minutes == 15 ? [] : ["Plan is \(plan.minutes) minutes, not 15"])
        }

        // C · Choosing what to learn
        await run("c1_search_then_open", "C", "Searches the real library, then opens and downloads the first result") {
            let s = try session(client: client)
            _ = await ask(s, "Find me an easy Bach piece in the library.")
            guard Self.has(appNotes(s), ["#1 "]) else { return (s, ["No library results came back: \(appNotes(s))"]) }
            let before = s.referenceURL
            _ = await ask(s, "Open the first one.")
            await until(45) { s.referenceURL != before || Self.has(self.appNotes(s), ["could not be"]) }
            return (s, s.referenceURL != before && s.tab == .practice ? [] : ["The piece wasn't opened: \(appNotes(s))"])
        }

        // D · Theory, technique and ear
        await run("d1_scale_exercise", "D", "“Teach me G major” opens a generated, graded scale exercise") {
            let s = try session(client: client)
            _ = await ask(s, "Teach me the G major scale with my right hand, one octave.")
            let title = s.tutorTitle
            var f: [String] = []
            if !Self.has(title, ["G major"]) { f.append("The open piece is “\(title)”, not a G major exercise: \(appNotes(s))") }
            if s.tutor == nil { f.append("No graded practice was prepared") }
            return (s, f)
        }
        await run("d2_play_chord", "D", "Demonstrates a chord with playNotes") {
            let s = try session(client: client)
            _ = await ask(s, "What does a C major chord sound like? Play it for me.")
            // Tests run without audio output, so the app answers that it couldn't play.
            return (s, Self.has(appNotes(s), ["Playing ", "piano couldn't play"]) ? [] : ["No notes were played: \(appNotes(s))"])
        }
        await run("d3_ear_training", "D", "Opens ear training for hearing major vs minor") {
            let s = try session(client: client)
            _ = await ask(s, "I can't hear the difference between major and minor. Can you quiz me?")
            return (s, s.lessonRunner.course == .ear && s.lessonRunner.page != nil ? [] : ["Ear training wasn't opened: \(appNotes(s))"])
        }

        // E · Progress and motivation
        await run("e1_last_time", "E", "Remembers the previous conversation through its own notes") {
            let s = try session(client: client)
            _ = await ask(s, "Help me with the left hand in bar 4, it's slow.")
            let learner = try XCTUnwrap(s.learner?.id)
            s.resetTutorChat() // New chat: the real model writes the note
            await until(45) { !s.tutorChatMemory(for: learner).notes().isEmpty }
            guard !s.tutorChatMemory(for: learner).notes().isEmpty else { return (s, ["No note was written for the finished chat"]) }
            let reply = await ask(s, "What did we work on last time?")
            return (s, Self.has(reply, ["bar 4", "left hand"]) ? [] : ["Reply doesn't recall bar 4 or the left hand: \(reply)"])
        }
        await run("e2_weekly_progress", "E", "Answers “how did I do this week” from real practice sessions") {
            let s = try session(client: client)
            await play(s); await play(s, wrongAt: [2])
            let reply = await ask(s, "How much have I practised this week?")
            return (s, Self.has(reply, ["min", "this week", "take"]) ? [] : ["Reply doesn't use the week's practice: \(reply)"])
        }
        await run("e3_dated_goal", "E", "Saves a goal with its target date") {
            let s = try session(client: client)
            let target = Self.day(45)
            _ = await ask(s, "My goal is to play Ode to Joy smoothly at full speed by \(target.text).")
            return (s, s.learnerSettings.tutorGoalDate == target.date ? [] : ["Goal date is \(String(describing: s.learnerSettings.tutorGoalDate)): \(appNotes(s))"])
        }

        // F · App help
        await run("f1_cant_hear_me", "F", "After a take where few notes were heard, points at the input or calibration") {
            let s = try session(client: client)
            await play(s, upTo: 3)
            let reply = await ask(s, "It doesn't seem to hear most of what I play.")
            let helps = Self.has(reply, ["calibrat", "MIDI", "microphone", "mic", "input"]) || s.tutorChatConfirmation != nil
            return (s, helps ? [] : ["Reply doesn't address the input: \(reply)"])
        }
        await run("f2_change_teacher", "F", "Finds the teacher setting from the app guide") {
            let s = try session(client: client)
            let reply = await ask(s, "How do I change my teacher to Kriti?")
            return (s, Self.has(reply, ["unit map", "Teacher menu", "Learn"]) ? [] : ["Reply doesn't say where: \(reply)"])
        }
        await run("f3_switch_input_waits", "F", "Offers to switch input and changes nothing until tapped") {
            let s = try session(client: client)
            let before = s.chosenInput
            _ = await ask(s, "Switch me to the computer keyboard please.")
            var f: [String] = []
            if !Self.has(s.tutorChatConfirmation?.label ?? "", ["computer keyboard"]) { f.append("No switch button offered: \(appNotes(s))") }
            if s.chosenInput != before { f.append("Input changed before the learner tapped") }
            return (s, f)
        }
        await run("f4_played_it_right", "F", "Keeps a disputed take (the bar the grader flagged) for checking, without regrading") {
            let s = try session(client: client)
            await play(s, wrongAt: [1])
            let score = s.report?.notes.score
            // Ask about the bar the grader actually flagged (the piece opens with rests).
            guard let flagged = s.report?.results.first(where: { $0.kind != .correct })?.position.measure else {
                return (s, ["The grader flagged nothing to dispute"])
            }
            _ = await ask(s, "Bar \(flagged) was marked wrong but I'm sure I played it right.")
            let kept = (try? FileManager.default.contentsOfDirectory(atPath: BookLibrary.support.appendingPathComponent("PlayedRight").path)) ?? []
            var f: [String] = []
            if kept.isEmpty { f.append("The take wasn't kept: \(appNotes(s))") }
            if s.report?.notes.score != score { f.append("The grade changed") }
            return (s, f)
        }

        // G · Children
        await run("g1_child_what_note", "G", "Child in a real Learn lesson: names the next note simply") {
            let s = try session(.child, piece: nil, client: client)
            s.lessonRunner.selectCourse(.piano); s.openStockLesson("p1")
            s.askTutorAsChild(TutorChildPrompts.whatNote); await answer(s)
            let reply = lastReply(s)
            var f: [String] = []
            if reply.split(separator: " ").count > 70 { f.append("Too long for a child (\(reply.split(separator: " ").count) words)") }
            if Self.has(reply, ["%", "BPM", "score"]) { f.append("Grading words for a child: \(reply)") }
            if !Self.has(reply, ["C", "D", "E"]) { f.append("Doesn't name a note: \(reply)") }
            return (s, f)
        }
        await run("g2_child_slower", "G", "Child: “Make it slower” slows the exercise") {
            let s = try session(.child, client: client)
            let before = s.tempoPercent
            s.askTutorAsChild(TutorChildPrompts.slower); await answer(s)
            return (s, s.tempoPercent < before ? [] : ["Speed stayed at \(Int(s.tempoPercent))%: \(appNotes(s))"])
        }
        await run("g3_grown_up", "G", "Grown-up: answers in adult language from the child's real progress") {
            let s = try session(.child, client: client)
            await play(s); await play(s, wrongAt: [3])
            s.askTutorAsChild(TutorChildPrompts.grownUps); await answer(s)
            let reply = lastReply(s)
            var f: [String] = []
            if !Self.has(reply, ["min", "take", "practis", "week"]) { f.append("Doesn't report progress: \(reply)") }
            if !s.tutorChat.turns.filter({ $0.role == .app }).isEmpty { f.append("An action ran for the grown-up's question") }
            return (s, f)
        }

        try Self.write(outcomes, model: client.model)
        let failed = outcomes.filter { !$0.passed }
        XCTAssertTrue(failed.isEmpty, "\(failed.count) of \(outcomes.count) live scenarios failed: \(failed.map(\.id))")
    }

    // MARK: Report

    static func write(_ outcomes: [Outcome], model: String) throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(outcomes).write(to: docs.appendingPathComponent("tutor_live_evaluation.json"), options: .atomic)
        let passed = outcomes.filter(\.passed).count
        let date = ISO8601DateFormatter().string(from: Date())
        var md = ["# Tutor live evaluation", "",
                  "Model `\(model)`, \(date). The real app end to end: real pieces and graded takes, library, lessons, memory and action checks; only the model is live.", "",
                  "**\(passed) of \(outcomes.count) passed.** Regenerate: `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`.", "",
                  "| Scenario | Case | Result | Seconds | What happened |", "|---|---|---|---|---|"]
        for o in outcomes {
            let what = o.passed ? o.description : o.failures.joined(separator: "; ")
            md.append("| \(o.scenario) | `\(o.id)` | \(o.passed ? "✅" : "❌") | \(o.seconds) | \(what.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ").prefix(300)) |")
        }
        md += ["", "## Transcripts", ""]
        for o in outcomes {
            md += ["### \(o.id)", ""] + o.transcript.map { "- " + $0.replacingOccurrences(of: "\n", with: " ") } + [""]
        }
        try md.joined(separator: "\n").write(to: docs.appendingPathComponent("tutor_live_evaluation.md"), atomically: true, encoding: .utf8)
    }
}
#endif
