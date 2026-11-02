#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
@testable import PianoPad

final class ModelLessonPlanTests: XCTestCase {
    let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test")

    func testAsksMuseSparkWithTheSchema() async throws {
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "planner")
            let format = body["response_format"] as? [String: Any]
            XCTAssertEqual(format?["type"] as? String, "json_schema")
            let messages = body["messages"] as! [[String: Any]]
            XCTAssertTrue((messages[1]["content"] as! String).contains("bar 1"))
            let reply = #"{"phrases":[{"startBar":1,"endBar":2,"label":"A","tip":"Lift at the end."}],"handsSeparately":false,"reason":"r"}"#
            let wrapped = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]])
            return (wrapped, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        var notes: [NoteEvent] = []
        for i in 0..<8 {
            let beat = Double(i)
            notes.append(NoteEvent(pitch: 60 + i % 3, onset: beat * 0.5, offset: beat * 0.5 + 0.45, onsetBeats: beat, offsetBeats: beat + 1))
        }
        let piece = MIDISequence(notes: notes)
        let plan = await LessonPlanner.plan(for: piece, title: "Two bars", model: ModelLessonPlanModel(client: client, model: "planner"), known: [])
        XCTAssertEqual(plan.source, .model)
        XCTAssertEqual(plan.phrases.first?.tip, "Lift at the end.")
    }

    /// One real request: Muse Spark plans Ode to Joy from the Starter Book's answer key.
    func testOneLivePlanWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIANOAI_PLANNER_LIVE"] == "1", "Set PIANOAI_PLANNER_LIVE=1 for one real planning request")
        try XCTSkipIf(APIKeyStore.key(for: .meta) == nil, "No configured Meta key")
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/starter/midi/ode-to-joy.midi")
        let piece = try MIDIFile.read(url: url)
        let plan = await LessonPlanner.plan(for: piece, title: "Ode to Joy", model: try ModelLessonPlanModel.configured(),
                                            known: LessonPlan.startingNotes, log: { print("[LessonPlanner] \($0)") })
        print("Plan (\(plan.source)): " + plan.phrases.map { "\($0.label) \($0.bars) \($0.tip ?? "")" }.joined(separator: " | ")
              + " hands separately: \(plan.handsSeparately); new: \(plan.newNotes.map(\.note.name)); reason: \(plan.reason ?? "")")
        XCTAssertEqual(plan.source, .model)
        XCTAssertEqual(LessonPlanCheck.errors(plan, measureCount: piece.measureCount, hasTwoHands: piece.hasTwoHands), [])
    }
}
#endif

#if os(macOS)
private struct OfflinePlanner: LessonPlanModel {
    func propose(system: String, user: String, schemaName: String, schema: String) async throws -> String {
        throw URLError(.notConnectedToInternet)
    }
}

extension ModelLessonPlanTests {
    /// Teach me this piece, offline: a quick plan, followed step by step, and its Learn page.
    @MainActor func testPlannedLessonOfflineAndLearnPage() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("PieceLessons-\(UUID().uuidString)")
        PieceLessonStore.rootOverride = temp
        defer { PieceLessonStore.rootOverride = nil; try? FileManager.default.removeItem(at: temp) }
        let session = PlaySession(startServices: false)
        session.learner = nil
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        session.loadReference(root.appendingPathComponent("Fixtures/starter/midi/ode-to-joy.midi"), remember: false)
        session.tutorPlanModel = OfflinePlanner()
        session.beginTutoring(planLesson: true, ignoreReadiness: true)
        for _ in 0..<200 where session.tutorPlanning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(session.tutorPlanning)
        let engine = try XCTUnwrap(session.tutor)
        XCTAssertTrue(engine.isFollowingPlan)
        XCTAssertEqual(engine.plan?.source, .fallback)
        XCTAssertEqual(engine.plan?.phrases.map(\.bars), [1...4, 5...8])
        XCTAssertEqual(engine.plan?.handsSeparately, true)
        XCTAssertEqual(engine.exercise.kind, .placement)
        session.tutor?.skip()
        XCTAssertEqual(session.tutor?.exercise.kind, .listen)
        // Listening moves straight on; the first note-by-note step plays one hand.
        session.startTutorExercise()
        XCTAssertNotEqual(session.tutor?.exercise.kind, .listen)
        while let e = session.tutor?.exercise, e.kind == .newNote { session.tutor?.skip() }
        XCTAssertEqual(session.tutor?.exercise.hand, .right)
        session.startTutorExercise()
        XCTAssertEqual(session.mode, .wait)
        let right = try XCTUnwrap(session.tutorFullReference).hand(.right).measures(1...4).notes.count
        XCTAssertEqual(session.reference?.notes.count, right)
        session.endTutoring()
        // The Learn page was written, and loads as the My pieces unit.
        let unit = try XCTUnwrap(PieceLessonStore.unit())
        XCTAssertEqual(unit.unit.pages.count, 1)
        XCTAssertEqual(unit.validate(), [])
        XCTAssertEqual(unit.unit.pages[0].blocks.last?.kind, .songChallenge)
    }
}
#endif
