import XCTest
import PianoGraderCore
@testable import PianoLessons

final class TutorCoachingTests: XCTestCase {
    func report() -> GradeReport {
        let ref = MIDISequence(notes: (0..<8).map { i in
            NoteEvent(pitch: 60 + i, onset: Double(i) * 0.5, offset: Double(i) * 0.5 + 0.4, onsetBeats: Double(i))
        })
        return Grader().grade(reference: ref, take: ref)
    }
    func testFastPlayingGetsHumanEvaluationAndSlowInvitation() {
        var r = report()
        r.timing?.tempoDeviation = 0.3
        let text = TutorCoaching.message(report: r, next: .init(kind: .slow, measures: 2...2, tempoPercent: 70), mastered: false, printedMeasures: [7])
        XCTAssertTrue(text.contains("faster than the target"))
        XCTAssertTrue(text.contains("bar 7 again slowly"))
        XCTAssertFalse(text.contains("%"))
        XCTAssertFalse(text.contains("interval error"))
    }
    func testSlowRecommendationDoesNotInventRushing() {
        var r = report()
        r.timing = nil
        let text = TutorCoaching.message(report: r, next: .init(kind: .slow, measures: 1...1), mastered: false, printedMeasures: [1])
        XCTAssertTrue(text.contains("couldn't judge the timing"))
        XCTAssertFalse(text.contains("faster"))
        XCTAssertFalse(text.contains("rushed"))
    }
    func testNoteMistakeGetsSpecificCorrectionAndPracticeCue() {
        var r = report()
        r.results[0].kind = .wrongPitch
        r.results[0].expectedPitch = 64
        r.results[0].playedPitch = 62
        r.results[0].position.measure = 3
        let text = TutorCoaching.message(report: r, next: .init(kind: .notes, measures: 3...3), mastered: false, printedMeasures: [3])
        XCTAssertTrue(text.contains("D instead of E in bar 3"))
        XCTAssertTrue(text.contains("one note at a time"))
    }
    func testNoteLearningIsNotCalledMastery() {
        let text = TutorCoaching.message(report: report(), next: .init(kind: .slow, measures: 1...1), mastered: false, printedMeasures: [1], notesCompleted: true)
        XCTAssertTrue(text.contains("worked through the notes"))
        XCTAssertFalse(text.contains("passed this piece"))
    }
}
