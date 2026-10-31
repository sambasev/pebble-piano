#if os(macOS)
import AppKit
import SwiftUI

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
    @StateObject private var session = PlaySession()
    @AppStorage(Usage.defaultsKey) private var shareUsage = true

    init() {
        // Before any window: the analytics session starts with the app.
        Usage.start()
    }

    var body: some Scene {
        WindowGroup("PerfectPiano") {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 1040, minHeight: 780)
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
