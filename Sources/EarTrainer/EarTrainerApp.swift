#if os(macOS)
import AppKit
import SwiftUI
import EarTrainingUI

final class EarTrainerDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct EarTrainerApp: App {
    @NSApplicationDelegateAdaptor(EarTrainerDelegate.self) private var delegate
    @StateObject private var session = EarTrainingSession()
    var body: some Scene {
        Window("EarTrainer", id: "ear-training") {
            EarTrainingView(session: session)
                .frame(minWidth: 1000, minHeight: 740)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    session.stop()
                }
        }
        .defaultSize(width: 1120, height: 850)
        .windowResizability(.contentMinSize)
    }
}
#else
@main enum EarTrainerUnavailable {
    static func main() { print("EarTrainer is a macOS app.") }
}
#endif
