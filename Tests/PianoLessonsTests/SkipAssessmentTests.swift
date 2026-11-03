import XCTest
import PianoGraderCore
@testable import PianoLessons

final class SkipAssessmentTests: XCTestCase {
    private let plan = LessonPlan(phrases: [.init(bars: 1...4, label: "Phrase 1"), .init(bars: 5...8, label: "Phrase 2")],
                                  handsSeparately: true, source: .model)

    /// A run stopped after `bars`: the session drops the bars not reached from the report.
    private func stopped(after bars: Int, take: MIDISequence, piece: MIDISequence) -> GradeReport {
        var reference = piece
        reference.notes.removeAll { $0.onsetBeats >= Double(bars * 4) }
        var report = Grader().grade(reference: reference, take: take)
        report.results.removeAll { $0.position.measure > bars }
        report.flags.removeAll { $0.position.measure > bars }
        report.passed = false
        return report
    }

    func testSkippingPassageByPassageGoesStraightIntoTime() {
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        XCTAssertEqual(engine.exercise.kind, .placement)
        engine.skipAssessment(pace: .passageByPassage)
        XCTAssertEqual(engine.pace, .passageByPassage)
        XCTAssertEqual(engine.exercise.kind, .listen)
        let phrases = engine.steps.filter { $0.label != nil }.map { "\($0.kind.rawValue) \($0.measures.lowerBound)-\($0.measures.upperBound)" }
        XCTAssertEqual(phrases, ["slow 1-4", "fullSpeed 1-4", "slow 5-8", "fullSpeed 5-8", "slow 1-8"])
        // Kept when the lesson is resumed.
        var resumed = PiecePracticeEngine(measureCount: 8, plan: plan)
        XCTAssertTrue(resumed.restore(engine.progress!))
        XCTAssertEqual(resumed.pace, .passageByPassage)
        XCTAssertEqual(resumed.steps.map(\.key), engine.steps.map(\.key))
        XCTAssertEqual(resumed.exercise, engine.exercise)
    }

    func testSkippingNoteByNoteKeepsTheFullPlan() {
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        let before = engine.steps.map(\.key)
        engine.skipAssessment(pace: .noteByNote)
        XCTAssertEqual(engine.steps.map(\.key), before)
        XCTAssertEqual(engine.exercise.kind, .listen)
    }

    func testChangingPaceMidLessonKeepsWhatsDone() {
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        engine.skip(); engine.completeStep()
        XCTAssertEqual(engine.exercise.kind, .notes)
        XCTAssertEqual(engine.exercise.hand, .right)
        engine.setPace(.passageByPassage)
        XCTAssertEqual(engine.completedSteps.count, 2)
        XCTAssertEqual(engine.exercise.kind, .slow, "the note-by-note step went; on to the first step still to do")
        XCTAssertEqual(engine.exercise.measures, 1...4)
    }

    func testStoppingShowMeWhatYouCanDoGradesOnlyThePhrasesPlayed() {
        let piece = twoHandPiece(bars: 8)
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        engine.setPace(.passageByPassage)
        var take = piece
        take.notes.removeAll { $0.onsetBeats >= 16 }   // stopped after bar 4
        engine.record(stopped(after: 4, take: take, piece: piece), playedThrough: 4)
        XCTAssertEqual(engine.grades[0], .clean)
        XCTAssertNil(engine.grades[1], "phrase 2 wasn't reached")
        XCTAssertTrue(engine.steps.filter { $0.label == "Phrase 1" }.allSatisfy { $0.skipReason != nil })
        let phrase2 = engine.steps.filter { $0.label == "Phrase 2" }.map(\.kind)
        XCTAssertEqual(phrase2, [.slow, .fullSpeed])
        XCTAssertFalse(engine.steps.contains { $0.kind == .listen && engine.completedSteps.contains(engine.steps.firstIndex(of: $0)!) },
                       "a part-run doesn't skip listening")
    }

    func testStoppingAPlayedMidPhraseLeavesThatPhraseUngraded() {
        let piece = twoHandPiece(bars: 8)
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        var take = piece
        take.notes.removeAll { $0.onsetBeats >= 8 }    // stopped after bar 2
        engine.record(stopped(after: 2, take: take, piece: piece), playedThrough: 2)
        XCTAssertTrue(engine.grades.isEmpty)
        XCTAssertEqual(engine.exercise.kind, .listen)
    }

    func testStoppingACleanAssessmentLearnsTheNextPart() {
        let piece = twoHandPiece(bars: 8)
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        engine.assessInstead()
        engine.setPace(.noteByNote)
        XCTAssertEqual(engine.exercise.kind, .assessment)
        var take = piece
        take.notes.removeAll { $0.onsetBeats >= 20 }   // stopped after bar 5
        engine.record(stopped(after: 5, take: take, piece: piece), playedThrough: 5)
        XCTAssertFalse(engine.mastered)
        XCTAssertEqual(engine.exercise.kind, .notes)
        XCTAssertEqual(engine.exercise.measures, 6...8, "the part not yet played, from where the run stopped")
        XCTAssertEqual(engine.exercise.label, "Phrase 2")
    }

    func testStoppingAnAssessmentWithMistakesDrillsThem() {
        let piece = twoHandPiece(bars: 8)
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        engine.assessInstead()
        var take = piece
        take.notes.removeAll { $0.onsetBeats >= 16 }
        take.notes.removeAll { $0.onsetBeats >= 4 && $0.onsetBeats < 8 }   // bar 2 missing
        engine.record(stopped(after: 4, take: take, piece: piece), playedThrough: 4)
        XCTAssertFalse(engine.mastered)
        XCTAssertTrue(engine.exercise.measures.upperBound <= 4, "drills stay on the bars played")
    }

    func testSkippingTheAdaptiveAssessmentReturnsToThePlan() {
        var engine = PiecePracticeEngine(measureCount: 8, plan: plan)
        engine.skip(); engine.completeStep()
        engine.assessInstead()
        engine.skip()
        XCTAssertTrue(engine.isFollowingPlan)
        XCTAssertEqual(engine.exercise.kind, .notes)
        // Without a plan: the piece in parts.
        var free = PiecePracticeEngine(measureCount: 8)
        free.skip()
        XCTAssertEqual(free.exercise.kind, .notes)
        XCTAssertEqual(free.exercise.measures, 1...4)
    }
}
