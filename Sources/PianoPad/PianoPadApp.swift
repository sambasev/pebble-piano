#if os(macOS)
import AppKit
import SwiftUI
import PianoPadState

/// A Swift package executable has no Info.plist, so make it a regular foreground app
/// with a Dock icon that receives key events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PianoPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: PlaySession
    @AppStorage(Usage.defaultsKey) private var shareUsage = true

    init() {
        #if DEBUG
        // Isolated UI verification: never create test learners or practice records in real history.
        if let path = ProcessInfo.processInfo.environment["PERFECTPIANO_PREVIEW_DATA"] {
            let store = LearnerStore(baseURL: URL(fileURLWithPath: path),
                                     defaults: UserDefaults(suiteName: "PerfectPiano.preview")!)
            _session = StateObject(wrappedValue: PlaySession(learnerStore: store))
            return
        }
        #endif
        _session = StateObject(wrappedValue: PlaySession())
        // Before any window: the analytics session starts with the app.
        Usage.start()
    }

    var body: some Scene {
        WindowGroup("PerfectPiano") {
            PPWindowFit { ContentView() }
                .environmentObject(session)
                // Full screen ignores this minimum (the 13" MacBook Neo is 752 pt tall, ~728 with
                // the menu bar), so PPWindowFit shrinks or scrolls the layout to fit whatever it gets.
                .frame(minWidth: 1040, minHeight: PP.WindowHeight.floor)
                .tint(PP.accent)
                .ppPaperStyle()
                .background(PPBackdrop())
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Toggle("Share Anonymous Usage Data", isOn: Binding(
                    get: { shareUsage },
                    set: { shareUsage = $0; Usage.setEnabled($0) }
                ))
            }
        }
    }
}
#else
@main
enum PianoPadUnavailable {
    static func main() {
        print("PianoPad is a macOS app.")
    }
}
#endif
