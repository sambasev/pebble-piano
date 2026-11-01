import XCTest
import PianoGraderCore
@testable import PianoLessons

/// Two hands, 4/4 at 120: the right hand plays four quarters a bar from `rh`, the left hand
/// a whole note a bar from `lh`. Upper staff on track 0, lower on track 1, as book imports write.
func twoHandPiece(bars: Int, rh: [Int] = [64, 64, 65, 67], lh: [Int] = [48, 43]) -> MIDISequence {
    var notes: [NoteEvent] = []
    for bar in 0..<bars {
        for beat in 0..<4 {
            let q = Double(bar * 4 + beat)
            // The last beat of every fourth bar is held: a cadence.
            let held = (bar % 4 == 3 && beat == 0) ? 4.0 : 1.0
            if bar % 4 == 3 && beat > 0 { continue }
            notes.append(NoteEvent(pitch: rh[(bar + beat) % rh.count], onset: q * 0.5, offset: (q + held) * 0.5 - 0.05,
                                   onsetBeats: q, offsetBeats: q + held, track: 0))
        }
        let q = Double(bar * 4)
        notes.append(NoteEvent(pitch: lh[bar % lh.count], onset: q * 0.5, offset: (q + 4) * 0.5 - 0.05,
                               onsetBeats: q, offsetBeats: q + 4, track: 1))
    }
    return MIDISequence(notes: notes)
}

struct FakePlanModel: LessonPlanModel {
    let replies: [String]
    let calls = Calls()
    final class Calls: @unchecked Sendable { var users: [String] = [] }
    func propose(system: String, user: String, schemaName: String, schema: String) async throws -> String {
        calls.users.append(user)
        let i = min(calls.users.count - 1, replies.count - 1)
        if replies[i] == "THROW" { throw URLError(.timedOut) }
        return replies[i]
    }
}

final class LessonPlanTests: XCTestCase {
    func phrase(_ r: ClosedRange<Int>) -> LessonPlan.Phrase { .init(bars: r, label: "P") }

    // MARK: Hands

    func testHandTracksAndSlicing() {
        let piece = twoHandPiece(bars: 2)
        XCTAssertEqual(piece.handTracks, [.right: 0, .left: 1])
        XCTAssertTrue(piece.hand(.right).notes.allSatisfy { $0.track == 0 })
        XCTAssertTrue(piece.hand(.left).notes.allSatisfy { $0.track == 1 })
        XCTAssertEqual(piece.hand(nil).notes.count, piece.notes.count)
        let one = MIDISequence(notes: piece.notes.filter { $0.track == 0 })
        XCTAssertNil(one.handTracks)
        XCTAssertEqual(one.hand(.left).notes.count, one.notes.count, "one part can't be split: unchanged")
    }

    // MARK: Checks

    func testValidPlanHasNoErrors() {
        let plan = LessonPlan(phrases: [phrase(1...4), phrase(5...8)], handsSeparately: true, source: .model)
        XCTAssertEqual(LessonPlanCheck.errors(plan, measureCount: 8, hasTwoHands: true), [])
    }

    func testGapsOverlapsEndsAndHandsAreCaught() {
        let gap = LessonPlan(phrases: [phrase(1...3), phrase(5...8)], handsSeparately: false, source: .model)
        XCTAssertEqual(LessonPlanCheck.errors(gap, measureCount: 8, hasTwoHands: true), [.gap(after: 3)])
        let overlap = LessonPlan(phrases: [phrase(1...4), phrase(4...8)], handsSeparately: false, source: .model)
        XCTAssertEqual(LessonPlanCheck.errors(overlap, measureCount: 8, hasTwoHands: true), [.overlap(at: 4)])
        let short = LessonPlan(phrases: [phrase(2...4)], handsSeparately: true, source: .model)
        XCTAssertEqual(LessonPlanCheck.errors(short, measureCount: 6, hasTwoHands: false),
                       [.doesNotStartAtBarOne(2), .doesNotEndAtLastBar(expected: 6, got: 4), .handsUnavailable])
        let long = LessonPlan(phrases: [phrase(1...9)], handsSeparately: false, source: .model)
        XCTAssertEqual(LessonPlanCheck.errors(long, measureCount: 9, hasTwoHands: true), [.tooLong(start: 1, end: 9)])
        XCTAssertEqual(LessonPlanCheck.errors(LessonPlan(phrases: [], handsSeparately: false, source: .model),
                                              measureCount: 4, hasTwoHands: true), [.noPhrases])
    }

    // MARK: Fallback

    func testFallbackCoversEveryBarOnceAndEndsOnCadences() {
        for bars in [1, 3, 4, 5, 8, 9, 12, 13, 16] {
            let piece = twoHandPiece(bars: bars)
            let plan = LessonPlan.fallback(for: piece)
            XCTAssertEqual(LessonPlanCheck.errors(plan, measureCount: bars, hasTwoHands: true), [], "\(bars) bars: \(plan.phrases.map(\.bars))")
            XCTAssertEqual(plan.source, .fallback)
            XCTAssertTrue(plan.handsSeparately)
        }
        XCTAssertEqual(LessonPlan.fallback(for: twoHandPiece(bars: 8)).phrases.map(\.bars), [1...4, 5...8])
        XCTAssertEqual(LessonPlan.fallback(for: twoHandPiece(bars: 4)).phrases.map(\.bars), [1...4])
    }

    // MARK: New notes

    func testNewNotesAreUnknownPitchesInOrderWithHandAndFinger() {
        let piece = twoHandPiece(bars: 2)
        let fingering = [FingeredNote(pitch: 65, quarter: 2, hand: .right, finger: 4)]
        let notes = LessonPlan.newNotes(in: piece, known: LessonPlan.startingNotes, fingering: fingering)
        XCTAssertEqual(notes.map(\.note.name), ["C3", "G2"])
        XCTAssertEqual(notes.first?.hand, .left)
        let withF = LessonPlan.newNotes(in: piece, known: [64, 67, 48, 43], fingering: fingering)
        XCTAssertEqual(withF.map(\.note.name), ["F4"])
        XCTAssertEqual(withF.first?.finger, 4)
        XCTAssertTrue(withF.first!.introduction.contains("finger 4 of your right hand"))
        XCTAssertEqual(LessonPlan.newNotes(in: piece, known: [], limit: 2).count, 2)
    }

    // MARK: The planner

    let good = """
    {"phrases":[{"startBar":1,"endBar":4,"label":"Question","tip":"Keep the thumb on E."},
                {"startBar":5,"endBar":8,"label":"Answer","tip":""}],
     "handsSeparately":true,"reason":"Two four-bar phrases."}
    """

    func testModelPlanIsUsedWhenItChecksOut() async {
        let model = FakePlanModel(replies: [good])
        let plan = await LessonPlanner.plan(for: twoHandPiece(bars: 8), title: "Test", model: model, known: LessonPlan.startingNotes)
        XCTAssertEqual(plan.source, .model)
        XCTAssertEqual(plan.phrases.map(\.bars), [1...4, 5...8])
        XCTAssertEqual(plan.phrases.map(\.label), ["Question", "Answer"])
        XCTAssertEqual(plan.phrases[0].tip, "Keep the thumb on E.")
        XCTAssertNil(plan.phrases[1].tip)
        XCTAssertEqual(plan.newNotes.map(\.note.name), ["C3", "G2"], "new notes come from code")
        XCTAssertEqual(model.calls.users.count, 1)
        XCTAssertTrue(model.calls.users[0].contains("bar 1 | RH: E4 1, E4 1, F4 1, G4 1 | LH: C3 4"), model.calls.users[0])
    }

    func testBadPlanIsRepairedOnce() async {
        let gap = """
        {"phrases":[{"startBar":1,"endBar":3,"label":"A","tip":""},{"startBar":5,"endBar":8,"label":"B","tip":""}],
         "handsSeparately":false,"reason":"x"}
        """
        let model = FakePlanModel(replies: [gap, good])
        let plan = await LessonPlanner.plan(for: twoHandPiece(bars: 8), title: "Test", model: model, known: [])
        XCTAssertEqual(plan.source, .model)
        XCTAssertEqual(model.calls.users.count, 2)
        XCTAssertTrue(model.calls.users[1].contains("No phrase covers the bar after bar 3."))
    }

    func testFallbackWhenRepairFailsOrModelIsMissingOrDown() async {
        let piece = twoHandPiece(bars: 8)
        let twiceBad = FakePlanModel(replies: ["not json", "{\"phrases\":[],\"handsSeparately\":false,\"reason\":\"\"}"])
        var plan = await LessonPlanner.plan(for: piece, title: "T", model: twiceBad, known: [])
        XCTAssertEqual(plan.source, .fallback)
        XCTAssertEqual(twiceBad.calls.users.count, 2)
        plan = await LessonPlanner.plan(for: piece, title: "T", model: nil, known: [])
        XCTAssertEqual(plan.source, .fallback)
        let down = FakePlanModel(replies: ["THROW"])
        plan = await LessonPlanner.plan(for: piece, title: "T", model: down, known: [])
        XCTAssertEqual(plan.source, .fallback)
        XCTAssertEqual(down.calls.users.count, 1, "a failed request isn't retried")
    }

    func testHandsSeparatelyIsTurnedOffForOnePart() async {
        let one = MIDISequence(notes: twoHandPiece(bars: 8).notes.filter { $0.track == 0 })
        let plan = await LessonPlanner.plan(for: one, title: "T", model: FakePlanModel(replies: [good]), known: [])
        XCTAssertEqual(plan.source, .model)
        XCTAssertFalse(plan.handsSeparately)
    }

    // MARK: Engine

    func testPlannedStepsInOrder() {
        var plan = LessonPlan(phrases: [.init(bars: 1...4, label: "Phrase 1"), .init(bars: 5...8, label: "Phrase 2")],
                              handsSeparately: true, source: .model)
        plan.newNotes = [.init(note: NoteName(pitch: 48), hand: .left)]
        let steps = PiecePracticeEngine.steps(for: plan, measureCount: 8, persona: .alex)
        let summary = steps.map { "\($0.kind.rawValue) \($0.measures.lowerBound)-\($0.measures.upperBound) \($0.hand?.rawValue ?? "")" }
        XCTAssertEqual(summary, [
            "listen 1-8 ", "newNote 1-8 L",
            "notes 1-4 R", "notes 1-4 L", "notes 1-4 ", "slow 1-4 ",
            "notes 5-8 R", "notes 5-8 L", "notes 5-8 ", "slow 5-8 ",
            "slow 1-8 ", "perform 1-8 ",
        ])
        let onePhrase = LessonPlan(phrases: [.init(bars: 1...4, label: "Phrase 1")], handsSeparately: false, source: .fallback)
        XCTAssertEqual(PiecePracticeEngine.steps(for: onePhrase, measureCount: 4, persona: .alex).map(\.kind),
                       [.listen, .notes, .slow, .perform])
    }

    func testFollowingThePlanToPerformThenAdaptiveWithPhrases() {
        let piece = twoHandPiece(bars: 8)
        let plan = LessonPlan(phrases: [.init(bars: 1...4, label: "Phrase 1"), .init(bars: 5...8, label: "Phrase 2")],
                              handsSeparately: false, source: .model)
        var engine = PiecePracticeEngine(measureCount: 8, persona: .alex, plan: plan)
        XCTAssertTrue(engine.isFollowingPlan)
        XCTAssertEqual(engine.exercise.kind, .listen)
        engine.completeStep()
        XCTAssertEqual(engine.exercise.kind, .notes)
        let clean = Grader().grade(reference: piece.measures(1...4), take: piece.measures(1...4))
        engine.record(clean, completedNotes: false)
        XCTAssertEqual(engine.exercise.kind, .notes, "an unfinished note-by-note run doesn't pass")
        engine.record(clean, completedNotes: true)
        XCTAssertEqual(engine.exercise.kind, .slow)
        XCTAssertEqual(engine.exercise.measures, 1...4)
        XCTAssertEqual(engine.completedSteps, [0, 1])
        // Jump to Perform; a weak performance goes to the adaptive drills, on the phrase.
        engine.jump(to: engine.steps.count - 1)
        XCTAssertEqual(engine.exercise.kind, .perform)
        var take = piece
        take.notes.removeAll { $0.onsetBeats >= 24 && $0.onsetBeats < 28 } // bar 7
        let weak = Grader().grade(reference: piece, take: take)
        engine.record(weak, stars: 1)
        XCTAssertEqual(engine.lastStars, 1)
        XCTAssertFalse(engine.mastered)
        XCTAssertFalse(engine.isFollowingPlan)
        XCTAssertEqual(engine.exercise.kind, .notes)
        XCTAssertEqual(engine.exercise.measures, 7...7, "note learning stays on the bar")
        engine.record(weak, completedNotes: true)
        XCTAssertEqual(engine.exercise.kind, .slow)
        XCTAssertEqual(engine.exercise.measures, 5...8, "the drills take the whole phrase")
        XCTAssertEqual(engine.exercise.label, "Phrase 2")
    }

    func testGoodPerformanceMastersThePiece() {
        let piece = twoHandPiece(bars: 4)
        var engine = PiecePracticeEngine(measureCount: 4, persona: .alex, plan: .fallback(for: piece))
        engine.jump(to: engine.steps.count - 1)
        engine.record(Grader().grade(reference: piece, take: piece), stars: 3)
        XCTAssertTrue(engine.mastered)
        XCTAssertEqual(engine.lastStars, 3)
        XCTAssertEqual(engine.completedSteps, [engine.steps.count - 1])
    }

    func testAssessInsteadLeavesThePlan() {
        var engine = PiecePracticeEngine(measureCount: 8, plan: .fallback(for: twoHandPiece(bars: 8)))
        engine.assessInstead()
        XCTAssertFalse(engine.isFollowingPlan)
        XCTAssertEqual(engine.exercise.kind, .assessment)
        XCTAssertNotNil(engine.plan, "the drills still use its phrases")
    }

    func testExerciseCodesBackwardsCompatibly() throws {
        let old = #"{"kind":"slow","measures":[2,3],"tempoPercent":70}"#
        let e = try JSONDecoder().decode(PracticeExercise.self, from: Data(old.utf8))
        XCTAssertNil(e.hand)
        let new = PracticeExercise(kind: .notes, measures: 1...4, hand: .left, label: "Phrase 1")
        XCTAssertEqual(try JSONDecoder().decode(PracticeExercise.self, from: JSONEncoder().encode(new)), new)
        XCTAssertEqual(new.title, "Left hand · learn note by note")
        XCTAssertEqual(new.whereText, "Phrase 1 (bars 1–4)")
    }

    // MARK: Learn page

    func testLessonPageForLearn() throws {
        let piece = twoHandPiece(bars: 8)
        var plan = LessonPlan(phrases: [.init(bars: 1...4, label: "Phrase 1", tip: "Thumb on C."), .init(bars: 5...8, label: "Phrase 2")],
                              handsSeparately: true, source: .model)
        plan.newNotes = [.init(note: NoteName(pitch: 48), hand: .left)]
        let out = PieceLessonBuilder.build(plan: plan, sequence: piece, title: "Test piece", id: "piece-test")
        XCTAssertEqual(out.page.blocks.map(\.kind), [.listen, .explain,
                                                    .wait, .wait, .wait, .timed,
                                                    .wait, .wait, .wait, .timed, .songChallenge])
        XCTAssertEqual(Set(out.files.keys), ["whole.mid", "phrase1.mid", "phrase1-R.mid", "phrase1-L.mid",
                                              "phrase2.mid", "phrase2-R.mid", "phrase2-L.mid"])
        XCTAssertTrue(out.files["phrase1-L.mid"]!.notes.allSatisfy { $0.track == 1 })
        XCTAssertEqual(out.page.hint(forBlock: 2), "Thumb on C.")
        if case .explain(let b) = out.page.blocks[1] { XCTAssertEqual(b.advanceOn, NoteName(pitch: 48)) } else { XCTFail() }
        // As a unit: paths under each piece's folder, every page open, and it checks out.
        let unit = PieceLessonBuilder.unit(pages: [(folder: "test", page: out.page), (folder: "other", page: LessonPage(id: "piece-other", title: "Other", blocks: out.page.blocks))])
        XCTAssertEqual(unit.pages[0].blocks.first?.midi, "test/whole.mid")
        XCTAssertTrue(unit.isUnlocked("piece-other", completed: []))
        let loaded = LoadedUnit(unit: unit, folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(loaded.validate(fileExists: { _ in true }).count, 0)
    }
}
