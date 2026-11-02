#if os(macOS)
import XCTest
import PianoLessons
import PianoPadState
@testable import PianoPad

/// Each learner comes back to where they left off, and nothing plays by itself.
final class ResumePlaceTests: XCTestCase {
    private var base: URL!
    private var suite: String!
    private var store: LearnerStore!
    private var a: Learner!
    private var b: Learner!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("ResumePlace-\(UUID().uuidString)")
        suite = "ResumePlace-\(UUID().uuidString)"
        store = LearnerStore(baseURL: base, defaults: UserDefaults(suiteName: suite)!)
        a = try store.add(name: "A", kind: .adult)
        b = try store.add(name: "B", kind: .adult)
        try store.setActive(a.id)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func session() -> PlaySession {
        let session = PlaySession(learnerStore: store, startServices: false)
        session.needsLearnerPick = false
        return session
    }

    /// Lets the tab's deferred change and the page opening run.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    private func example(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/\(name)").standardizedFileURL
    }

    func testEachLearnerGetsTheirOwnTab() {
        let session = session()
        session.tab = .books
        settle()
        session.switchLearner(to: b.id)
        settle()
        XCTAssertEqual(session.tab, .practice, "nothing saved yet")
        session.tab = .backingTracks
        settle()
        session.switchLearner(to: a.id)
        settle()
        XCTAssertEqual(session.tab, .books)
        XCTAssertEqual(store.settings(for: b.id).lastTab, "backingTracks")
    }

    func testEachLearnerGetsTheirOwnPiece() {
        let session = session()
        session.loadReference(example("ode-to-joy-c.mid"), remember: false)
        session.switchLearner(to: b.id)
        session.loadReference(example("five-finger.mid"), remember: false)
        session.switchLearner(to: a.id)
        XCTAssertEqual(session.referenceURL?.lastPathComponent, "ode-to-joy-c.mid")
        session.switchLearner(to: b.id)
        XCTAssertEqual(session.referenceURL?.lastPathComponent, "five-finger.mid")
    }

    func testAMissingPieceIsSkippedQuietly() throws {
        var settings = LearnerSettings()
        settings.lastPiece = "file:/nowhere/gone.mid"
        try store.save(settings, for: b.id)
        let session = session()
        session.switchLearner(to: b.id)
        XCTAssertNil(session.message)
        XCTAssertEqual(session.tab, .practice)
    }

    func testAnOpenLessonReopensAtItsStepWithoutPlaying() throws {
        let session = session()
        session.lessonRunner.arrive()
        let unit = try XCTUnwrap(session.lessonRunner.unit).unit
        // A listen step would normally start playing as soon as it's shown.
        var found: (page: String, step: Int)?
        for page in unit.pages {
            for (step, block) in page.blocks.enumerated() {
                if case .listen = block, found == nil { found = (page.id, step) }
            }
        }
        let target = try XCTUnwrap(found)
        try store.history(for: b.id).saveLessonPosition(unit: unit.id, page: target.page, block: target.step)
        var settings = LearnerSettings()
        settings.lastTab = "learn"
        settings.lastLessonPage = target.page
        try store.save(settings, for: b.id)

        session.switchLearner(to: b.id)
        settle()
        XCTAssertEqual(session.tab, .learn)
        XCTAssertEqual(session.lessonRunner.page?.id, target.page)
        XCTAssertEqual(session.lessonRunner.shownIndex, target.step)
        XCTAssertFalse(session.isAuditioning)

        // Back on the page list: that's where they come back to now.
        session.lessonRunner.backToUnit()
        XCTAssertNil(store.settings(for: b.id).lastLessonPage)
    }

    func testAPageLeftForAnotherTabIsForgotten() throws {
        let session = session()
        session.tab = .learn
        settle()
        let id = try XCTUnwrap(session.lessonRunner.unit?.unit.pages.first?.id)
        session.lessonRunner.open(id)
        XCTAssertEqual(store.settings(for: a.id).lastLessonPage, id)
        session.tab = .practice
        settle()
        XCTAssertNil(store.settings(for: a.id).lastLessonPage)
    }

    func testPickingTheSameLearnerAtLaunchResumes() throws {
        var settings = LearnerSettings()
        settings.lastTab = "books"
        try store.save(settings, for: a.id)
        let session = PlaySession(learnerStore: store, startServices: false)
        XCTAssertTrue(session.needsLearnerPick)
        session.pickLearner(a.id)
        settle()
        XCTAssertEqual(session.tab, .books)
    }
}
#endif
