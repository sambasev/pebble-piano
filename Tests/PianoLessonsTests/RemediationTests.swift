import XCTest
import PianoGraderCore
@testable import PianoLessons

final class RemediationTests: XCTestCase {
    /// A report with `flags` (kind, measure) and `results` (kind, measure, expected, played).
    private func report(flags: [(String, Int)] = [], results: [(String, Int, Int?, Int?)] = [],
                        passed: Bool = false, accuracy: Double = 0.8) throws -> GradeReport {
        let flagJSON = flags.map { #"{"kind":"\#($0.0)","position":{"measure":\#($0.1),"beat":1},"message":""}"# }
        let resultJSON = results.map { r -> String in
            var fields = [#""kind":"\#(r.0)""#, #""position":{"measure":\#(r.1),"beat":1}"#]
            if let e = r.2 { fields.append(#""expectedPitch":\#(e)"#) }
            if let p = r.3 { fields.append(#""playedPitch":\#(p)"#) }
            return "{" + fields.joined(separator: ",") + "}"
        }
        let json = """
        { "passed": \(passed), "rubricLevel": "beginner", "levels": [],
          "flags": [\(flagJSON.joined(separator: ","))], "results": [\(resultJSON.joined(separator: ","))],
          "notes": { "expected": 10, "correct": 8, "wrongPitch": 1, "missed": 1, "extra": 0,
                     "ignoredLeading": 0, "ignoredTrailing": 0, "accuracy": \(accuracy), "score": \(accuracy) } }
        """
        return try JSONDecoder().decode(GradeReport.self, from: Data(json.utf8))
    }

    // MARK: Worst bar

    func testWorstMeasureWeighsNoteMistakesOverTiming() throws {
        let r = try report(flags: [("late", 1), ("late", 1), ("late", 1), ("wrongPitch", 3), ("missed", 3)])
        XCTAssertEqual(RemediationPlanner.worstMeasure(in: [r]), 3)
    }

    func testWorstMeasureAddsUpRunsAndReplays() throws {
        let a = try report(flags: [("wrongPitch", 2)])
        let b = try report(flags: [("wrongPitch", 4)])
        XCTAssertEqual(RemediationPlanner.worstMeasure(in: [a, b]), 2) // tie: earlier bar
        XCTAssertEqual(RemediationPlanner.worstMeasure(in: [a, b], replays: [4: 1]), 4)
    }

    func testNothingToFix() throws {
        XCTAssertNil(RemediationPlanner.worstMeasure(in: [try report()]))
        XCTAssertNil(RemediationPlanner.worstMeasure(in: []))
    }

    // MARK: Drill steps

    func testDrillSteps() {
        let d = RemediationPlanner.drill(measure: 3, measureCount: 8, persona: .alex)
        XCTAssertEqual(d.steps.map(\.kind), [.notes, .slow, .fullSpeed, .context])
        XCTAssertEqual(d.steps.map(\.measures), [3...3, 3...3, 3...3, 2...4])
        XCTAssertEqual(d.steps[1].tempoPercent, 70)
        XCTAssertTrue(d.steps[0].isWaitMode)
    }

    func testDrillAtTheEdges() {
        XCTAssertEqual(RemediationPlanner.drill(measure: 1, measureCount: 4, persona: .alex).steps.last?.measures, 1...2)
        XCTAssertEqual(RemediationPlanner.drill(measure: 4, measureCount: 4, persona: .alex).steps.last?.measures, 3...4)
        // One bar: no context step. Out of range clamps.
        XCTAssertEqual(RemediationPlanner.drill(measure: 1, measureCount: 1, persona: .alex).steps.count, 3)
        XCTAssertEqual(RemediationPlanner.drill(measure: 9, measureCount: 4, persona: .alex).measure, 4)
    }

    func testAlexMovesOnAfterOneCleanRunOrFourTries() {
        var d = RemediationPlanner.drill(measure: 2, measureCount: 4, persona: .alex)
        XCTAssertEqual(d.record(clean: true), .nextStep(d.steps[1], movedOn: false))
        XCTAssertEqual(d.record(clean: false), .again(clean: false))
        XCTAssertEqual(d.record(clean: false), .again(clean: false))
        XCTAssertEqual(d.record(clean: false), .again(clean: false))
        XCTAssertEqual(d.record(clean: false), .nextStep(d.steps[2], movedOn: true))
        XCTAssertEqual(d.record(clean: true), .nextStep(d.steps[3], movedOn: false))
        XCTAssertEqual(d.record(clean: true), .finished(movedOn: false))
        XCTAssertTrue(d.isFinished)
    }

    func testKritiNeedsTwoCleanInARowAndNeverGivesUp() {
        var d = RemediationPlanner.drill(measure: 2, measureCount: 4, persona: .kriti)
        // Wait mode: once is enough.
        XCTAssertEqual(d.record(clean: true), .nextStep(d.steps[1], movedOn: false))
        XCTAssertEqual(d.record(clean: true), .again(clean: true))
        XCTAssertEqual(d.record(clean: false), .again(clean: false)) // streak broken
        for _ in 0..<10 { XCTAssertEqual(d.record(clean: false), .again(clean: false)) }
        XCTAssertEqual(d.record(clean: true), .again(clean: true))
        XCTAssertEqual(d.record(clean: true), .nextStep(d.steps[2], movedOn: false))
    }

    func testAskingToMoveOn() {
        var d = RemediationPlanner.drill(measure: 1, measureCount: 1, persona: .kriti)
        XCTAssertEqual(d.moveOn(), .nextStep(d.steps[1], movedOn: true))
        XCTAssertEqual(d.moveOn(), .nextStep(d.steps[2], movedOn: true))
        XCTAssertEqual(d.moveOn(), .finished(movedOn: true))
    }

    func testCleanRun() throws {
        XCTAssertTrue(RemediationPlanner.isClean(try report(passed: true, accuracy: 0.95), replays: 0))
        XCTAssertFalse(RemediationPlanner.isClean(try report(passed: true, accuracy: 0.95), replays: 1))
        // A few slips under the grader's 95% still pass a step at 80%…
        XCTAssertTrue(RemediationPlanner.isClean(try report(passed: false, accuracy: 0.82), replays: 0))
        XCTAssertFalse(RemediationPlanner.isClean(try report(passed: false, accuracy: 0.78), replays: 0))
        // …but not when the rhythm failed.
        var uneven = try report(passed: false, accuracy: 0.95)
        uneven.levels = [LevelResult(check: .rhythm, passed: false, value: 0.4, threshold: 0.25, detail: "")]
        XCTAssertFalse(RemediationPlanner.isClean(uneven, replays: 0))
    }

    // MARK: Explaining

    func testExplainsWrongNotesWithFingers() throws {
        let r = try report(results: [("wrongPitch", 2, 64, 62), ("wrongPitch", 2, 64, 62), ("correct", 2, 60, 60),
                                     ("missed", 3, 67, nil)])
        let lines = MistakeExplainer.explain(r, finger: MistakeExplainer.middleCFinger)
        XCTAssertEqual(lines, [
            "You played D instead of E in bar 2, twice. E is finger 3.",
            "You missed G in bar 3. G is finger 5.",
        ])
    }

    func testExplainsTimingOnlyWhereTheNotesWereRight() throws {
        let r = try report(flags: [("early", 4), ("early", 4), ("late", 2)], results: [("wrongPitch", 2, 64, 62)])
        XCTAssertEqual(MistakeExplainer.explain(r), [
            "Bar 4 rushed: wait for the click.",
            "You played D instead of E in bar 2.",
        ])
    }

    func testExplainLimit() throws {
        let r = try report(results: (1...5).map { ("missed", $0, 60, nil) })
        XCTAssertEqual(MistakeExplainer.explain(r, limit: 2).count, 2)
    }

    // MARK: Personas

    func testPersonasDiffer() {
        XCTAssertEqual(Persona.alex.rules.requiredStars, 1)
        XCTAssertEqual(Persona.kriti.rules.requiredStars, 2)
        XCTAssertFalse(Persona.alex.drill.startsAutomatically)
        XCTAssertTrue(Persona.kriti.drill.startsAutomatically)
        XCTAssertEqual(Persona.alex.playAlong, .gentle)
        XCTAssertEqual(Persona.kriti.playAlong, .standard)
        XCTAssertNotEqual(Persona.alex.say(.runAgain), Persona.kriti.say(.runAgain))
    }

    func testMessagesFillInAndFallBack() {
        XCTAssertEqual(Persona.kriti.say(.drillOffer, bar: 3), "Bar 3 needs work. We'll drill it now.")
        var p = Persona.kriti
        p.messages = [:]
        XCTAssertEqual(p.say(.stepDone, step: "Full speed"), "Great. Next: Full speed.")
    }

    func testLoadingFromAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("personas-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var custom = Persona.kriti
        custom.requiredStars = 3
        try JSONEncoder().encode(custom).write(to: folder.appendingPathComponent("kriti.json"))
        XCTAssertEqual(Persona.load("kriti", folder: folder).requiredStars, 3)
        XCTAssertEqual(Persona.load("alex", folder: folder), .alex) // no file: built in
        XCTAssertEqual(Persona.load("nobody", folder: nil), .alex)
        XCTAssertEqual(Persona.load(nil, folder: nil), .alex)
    }

    /// The bundled persona files decode and match the built-in copies' rules.
    func testBundledPersonaFiles() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lessons/personas")
        for builtIn in Persona.builtIn {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(builtIn.id).json"))
            let file = try JSONDecoder().decode(Persona.self, from: data)
            XCTAssertEqual(file, builtIn, builtIn.id)
        }
    }
}
