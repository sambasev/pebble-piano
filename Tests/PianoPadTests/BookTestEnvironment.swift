#if os(macOS)
import Foundation
import PianoAI
import PianoPadState
@testable import PianoPad

/// A Books model that can't touch the learner's own things: its library (saved pieces, readings
/// kept beside them) and its learners live in a temporary folder, with defaults of their own.
/// A read with nothing to check saves and opens the piece in Practice, so tests need this.
@MainActor
final class BookTestEnvironment {
    let folder: URL
    let session: PlaySession
    private let suite: String

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BookTests-\(UUID().uuidString)")
        suite = "BookTests-\(UUID().uuidString)"
        BookLibrary.supportOverride = folder.appendingPathComponent("Support")
        let store = LearnerStore(baseURL: folder.appendingPathComponent("Learners"), defaults: UserDefaults(suiteName: suite)!)
        session = PlaySession(learnerStore: store, startServices: false)
    }

    /// A model with no reader: every read and re-read fails until a test gives it one.
    func makeModel() -> BookImportModel {
        let model = BookImportModel(session: session)
        model.barReader = { _, _, _ in throw ModelError.missingKey(.meta) }
        return model
    }

    /// Stops what `model` still has under way (a read finishing in the background would otherwise
    /// save after the library has gone back to the real one), then removes everything.
    func tearDown(_ model: BookImportModel?) {
        model?.startOver()
        BookLibrary.supportOverride = nil
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
#endif
