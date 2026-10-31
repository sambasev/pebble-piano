#if canImport(Combine)
import XCTest
import PianoGraderCore
import EarTrainingUI

@MainActor private final class LessonAudio: EarPlayback {
    var callback: (@MainActor (Result<Void, EarPlaybackError>) -> Void)?
    func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) { callback = completion }
    func stop() {}
}
@MainActor private final class LessonStore: EarProgressStore {
    var value = EarProgress()
    var saves = 0
    func load() -> EarProgress { value }
    func save(_ progress: EarProgress) { value = progress; saves += 1 }
}
final class EarLessonSessionTests: XCTestCase {
    @MainActor func testShortChecksRetrySameNotePoolWithoutInflatingFullQuizProgress() async {
        let audio = LessonAudio(), store = LessonStore()
        let session = EarTrainingSession(playback: audio, store: store)
        var completions = 0
        session.onQuizCompleted = { result, _ in
            XCTAssertEqual(result.total, 5); XCTAssertEqual(result.correct, 4); completions += 1
        }
        session.startLessonQuiz(stage: EarStageID(level: 1, stage: 2), questions: 5, notes: [0, 2, 4, 5])
        XCTAssertEqual(session.examples.count, 4)
        session.playLessonExample(session.examples[0]); audio.callback?(.success(()))
        XCTAssertFalse(session.heardQuestion, "Labeled examples are learning aids, not a listen to the question")
        for i in 0..<5 {
            if i < 4 {
                session.playQuestion(); audio.callback?(.success(()))
                session.answer(session.question!.correctAnswer.id)
            } else { session.skip() }
            session.next()
        }
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(store.saves, 0)
        XCTAssertTrue(session.progress.stages.isEmpty)
        session.startQuiz(seed: 20)
        XCTAssertEqual(session.quiz?.questions.count, 5)
        XCTAssertTrue(session.quiz!.questions.flatMap(\.stimulus).allSatisfy { [0, 2, 4, 5].contains($0.pitch % 12) })
        session.select(.first); session.startQuiz(seed: 1)
        XCTAssertEqual(session.quiz?.questions.count, 10)
    }
}
#endif
