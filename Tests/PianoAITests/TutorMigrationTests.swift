import XCTest
@testable import PianoAI

final class TutorMigrationTests: XCTestCase {
    func testExistingSharedKeyIsUntouched() throws {
        try LegacyTutorKeyMigration.migrate(hasSharedKey: { true }, readLegacy: { XCTFail("Should not read old key"); return "old" }, saveShared: { _ in XCTFail("Must not overwrite") }, removeLegacy: { XCTFail("Must not remove") })
    }
    func testSuccessfulMigrationAndFailedSave() throws {
        var saved: String?
        var removed = false
        try LegacyTutorKeyMigration.migrate(hasSharedKey: { false }, readLegacy: { "old" }, saveShared: { saved = $0 }, removeLegacy: { removed = true })
        XCTAssertEqual(saved, "old"); XCTAssertTrue(removed)
        removed = false
        XCTAssertThrowsError(try LegacyTutorKeyMigration.migrate(hasSharedKey: { false }, readLegacy: { "old" }, saveShared: { _ in throw ModelError.keychain(-1) }, removeLegacy: { removed = true }))
        XCTAssertFalse(removed)
    }
    func testTutorModelCompatibilityAndDefault() {
        let name = "TutorSettingsTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AISettings(defaults: defaults)
        XCTAssertEqual(settings.tutorModel, MetaModels.spark)
        defaults.set("legacy-model", forKey: "TutorModel")
        XCTAssertEqual(settings.tutorModel, "legacy-model")
        settings.tutorModel = " shared-model "
        XCTAssertEqual(settings.tutorModel, "shared-model")
        settings.tutorModel = " "
        XCTAssertEqual(settings.tutorModel, MetaModels.spark)
    }
}
