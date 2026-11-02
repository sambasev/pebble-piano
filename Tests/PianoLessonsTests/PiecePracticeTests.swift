import XCTest
import PianoGraderCore
@testable import PianoLessons

final class PiecePracticeTests: XCTestCase {
    func reference() -> MIDISequence {
        MIDISequence(notes: (0..<16).map { i in
            NoteEvent(pitch: 60 + i % 5, onset: Double(i) * 0.5, offset: Double(i) * 0.5 + 0.4, onsetBeats: Double(i))
        })
    }
    func testPrintedRepeatMappingAndBoundary() throws {
        let exercise = PracticeExercise(kind: .notes, measures: 3...4)
        XCTAssertEqual(exercise.printedMeasure(1, playOrder: [7, 8, 7, 8]), 7)
        XCTAssertEqual(exercise.printedMeasure(2, playOrder: [7, 8, 7, 8]), 8)
        XCTAssertEqual(exercise.printedMeasure(1, playOrder: []), 3)
        let context = TutorAttemptContext(exercise: exercise, actualTempoPercent: 70, mode: "wait", printedMeasures: [7, 8])
        let decoded = try JSONDecoder().decode(TutorAttemptContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded.exercise, exercise)
    }
    func testCleanAssessmentAndReassess() {
        let ref = reference()
        let report = Grader().grade(reference: ref, take: ref)
        var engine = PiecePracticeEngine(measureCount: 4)
        engine.record(report)
        XCTAssertTrue(engine.mastered)
        engine.reassess()
        XCTAssertFalse(engine.mastered)
        XCTAssertEqual(engine.exercise.kind, .assessment)
    }
    func testMissedNotesStartNotesAndKeepOriginalBar() {
        let ref = reference()
        var take = ref
        take.notes.removeAll { $0.onsetBeats >= 8 && $0.onsetBeats < 12 }
        let report = Grader().grade(reference: ref, take: take)
        var engine = PiecePracticeEngine(measureCount: 4)
        engine.record(report)
        XCTAssertEqual(engine.exercise.kind, .notes)
        XCTAssertEqual(engine.exercise.measures, 3...3)
        XCTAssertEqual(engine.exercise.originalMeasure(1), 3)
        engine.record(report, completedNotes: false)
        XCTAssertEqual(engine.exercise.kind, .notes)
        engine.record(report, completedNotes: true)
        XCTAssertEqual(engine.exercise.kind, .slow)
        XCTAssertFalse(engine.mastered)
        engine.skip()
        XCTAssertFalse(engine.mastered)
    }
    func testTimingOnlyStartsSlowAndKritiRequiresStreak() {
        let ref = reference()
        var take = ref
        for i in take.notes.indices { take.notes[i].onset += i % 2 == 0 ? 0 : 0.35 }
        let bad = Grader().grade(reference: ref, take: take)
        var engine = PiecePracticeEngine(measureCount: 4, persona: .kriti)
        engine.record(bad)
        XCTAssertEqual(engine.exercise.kind, .slow)
        let clean = Grader().grade(reference: ref, take: ref)
        engine.record(clean)
        XCTAssertEqual(engine.cleanStreak, 1)
        engine.record(bad)
        XCTAssertEqual(engine.cleanStreak, 0)
        engine.record(clean)
        engine.record(clean)
        XCTAssertEqual(engine.exercise.kind, .fullSpeed)
    }

    func testAFewMissedNotesStillPass() {
        let ref = reference()
        var take = ref
        take.notes.removeAll { $0.onsetBeats == 5 || $0.onsetBeats == 10 } // 14 of 16
        let report = Grader().grade(reference: ref, take: take)
        XCTAssertFalse(report.passed) // under the grader's 95%
        var engine = PiecePracticeEngine(measureCount: 4)
        engine.record(report)
        XCTAssertTrue(engine.mastered)
        XCTAssertTrue(engine.lastRunPassedWithSlips)
        let text = TutorCoaching.message(report: report, next: engine.exercise, mastered: true, printedMeasures: [],
                                         passedWithSlips: engine.lastRunPassedWithSlips)
        XCTAssertTrue(text.contains("That's a pass"), text)
        XCTAssertTrue(text.contains("watch out"), text)

        // A drill step at full speed is done too, and the next one starts.
        engine.focus(on: [2])
        engine.skip(); engine.skip() // past note by note and slowly
        XCTAssertEqual(engine.exercise.kind, .fullSpeed)
        engine.record(report) // 88%: passes first time

        XCTAssertEqual(engine.exercise.kind, .context)
    }

    func testSilenceAndInsufficientTimingCannotMaster() {
        let ref = reference()
        var engine = PiecePracticeEngine(measureCount: 4)
        engine.record(Grader().grade(reference: ref, take: MIDISequence(notes: [])))
        XCTAssertEqual(engine.exercise.kind, .notes)
        XCTAssertFalse(engine.mastered)
        engine.reassess()
        var report = Grader().grade(reference: ref, take: ref)
        report.timing = nil
        engine.record(report)
        XCTAssertEqual(engine.exercise.kind, .slow)
        XCTAssertEqual(engine.exercise.measures, 1...4)
        XCTAssertFalse(engine.mastered)
    }
}
