import Foundation

/// How the app is running: the sandboxed, packaged app (TestFlight / App Store) or the
/// unsandboxed Swift package executable used during development.
public enum AppEnvironment {
    /// True inside the App Sandbox. The sandbox can only read files the user chose this
    /// launch, and writes under ~ land in the app's container.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Whether to save what the microphone hears (for tuning the detector). On for
    /// development runs; off in the packaged app unless the `RecordMicDebug` default is set:
    /// `defaults write <bundle id> RecordMicDebug -bool YES`.
    public static var recordsMicForDebugging: Bool {
        !isSandboxed || UserDefaults.standard.bool(forKey: "RecordMicDebug")
    }
}
