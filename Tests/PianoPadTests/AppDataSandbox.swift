#if os(macOS)
import Foundation
import PianoPadState
@testable import PianoPad

/// Keeps a test out of the learner's own app data: learners (with defaults of their own), the
/// book library, readings and piece lessons all live in a temporary folder until `remove()`.
final class AppDataSandbox {
    let folder: URL
    let store: LearnerStore
    private let suite: String

    init(_ name: String = "AppData") {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        suite = "\(name)-\(UUID().uuidString)"
        BookLibrary.supportOverride = folder.appendingPathComponent("Support")
        store = LearnerStore(baseURL: folder.appendingPathComponent("Learners"), defaults: UserDefaults(suiteName: suite)!)
    }

    func session() -> PlaySession { PlaySession(learnerStore: store, startServices: false) }

    func remove() {
        BookLibrary.supportOverride = nil
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
#endif
