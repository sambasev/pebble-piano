#if os(macOS)
import AppKit
import Foundation
import PianoGraderCore
import PianoLessons
import PianoPadState
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

/// Anonymous usage analytics for the beta, sent to TelemetryDeck: which screens are used,
/// for how long (active time only), and a few milestones (setup finished, pages completed).
/// Never audio, names or file names. Off with PerfectPiano ▸ Share Anonymous Usage Data.
///
/// Only the packaged app links TelemetryDeck (App/project.yml); the Swift package build
/// (`swift run PianoPad`) doesn't, and everything here does nothing there. Debug builds'
/// signals are marked as test signals by TelemetryDeck (see Test Mode in its dashboard).
/// Sessions (one per launch) are counted by TelemetryDeck itself.
enum Usage {
    static let appID = "862F0834-1FF0-4AAA-9F66-23E9C5BC798B"
    /// UserDefaults key for the opt-out (missing: on).
    static let defaultsKey = "shareUsageData"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private static var started = false

    /// At launch (from the App's init, so the session starts with the app).
    static func start() {
        #if canImport(TelemetryDeck)
        guard isEnabled, !started else { return }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        started = true
        #endif
    }

    /// The menu toggle.
    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        #if canImport(TelemetryDeck)
        if on {
            start()
        } else if started {
            TelemetryDeck.terminate()
            started = false
        }
        #endif
    }

    /// One signal. `value` is summed or averaged in the dashboard (seconds, stars).
    static func event(_ name: String, _ parameters: [String: String] = [:], value: Double? = nil) {
        #if canImport(TelemetryDeck)
        guard started else { return }
        TelemetryDeck.signal(name, parameters: parameters, floatValue: value)
        #endif
    }
}

/// Counts active time per place in the app and sends it as `Usage.activeTime` signals
/// (floatValue: seconds) when the place changes, the app goes to the background or quits,
/// and every 5 minutes. A second counts as active when the app is frontmost and the learner
/// clicked, typed or played a note in the last minute, or music is playing.
///
/// The place is read once a second from the app's state rather than reported by every
/// screen, so a new screen needs only a line in `currentPlace()`.
final class ActivityTracker {
    private unowned let session: PlaySession
    private var timer: Timer?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var lastInteraction = Date.distantPast
    private var place: [String: String]?
    private var seconds = 0.0

    /// No interaction (and no music) for this long stops the count.
    static let idleAfter: TimeInterval = 60
    /// Long stays are sent in pieces, so a crash or force quit loses at most this much.
    static let sendEvery: Double = 300

    init(session: PlaySession) {
        self.session = session
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) {
            [weak self] event in
            self?.interacted()
            return event
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let center = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.send() })
        }
    }

    deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    /// A click, key or played note.
    func interacted() { lastInteraction = Date() }

    private func tick() {
        let now = currentPlace()
        if now != place {
            send()
            place = now
        }
        guard NSApp.isActive else { return }
        let busy = Date().timeIntervalSince(lastInteraction) < Self.idleAfter || session.isPlayingAlong || session.isAuditioning
        if busy { seconds += 1 }
        if seconds >= Self.sendEvery { send() }
    }

    private func send() {
        defer { seconds = 0 }
        guard let place, seconds >= 1 else { return }
        Usage.event("Usage.activeTime", place, value: seconds)
    }

    /// Where the learner is: tab, and in Learn the page and step.
    private func currentPlace() -> [String: String] {
        var p: [String: String] = [:]
        guard let learner = session.learner else {
            p["screen"] = "setup"
            return p
        }
        p["learner"] = learner.kind == .child ? "child" : "adult"
        if let input = session.chosenInput { p["input"] = input.rawValue }
        switch session.tab {
        case .practice:
            p["screen"] = "practice"
            p["mode"] = session.mode.rawValue
            p["piece"] = session.passage != nil ? "book" : (session.reference != nil ? "midi" : "none")
            if session.mode == .playAlong { p["backingTrack"] = session.hasBackingTrack ? "yes" : "no" }
        case .books:
            p["screen"] = "books.\(session.bookImport.phase)"
        case .backingTracks:
            p["screen"] = "backingTracks"
        case .learn:
            let runner = session.lessonRunner
            guard let page = runner.page else {
                p["screen"] = runner.warmUp != nil ? "learn.warmUp" : "learn.unitMap"
                return p
            }
            p["page"] = page.id
            if runner.result != nil {
                p["screen"] = "learn.pageDone"
            } else if let block = runner.shownBlock {
                p["screen"] = runner.isWarmingUp ? "learn.warmUp" : "learn.step"
                p["step"] = String(runner.shownIndex + 1)
                p["stepKind"] = block.kind.rawValue
                if case .songChallenge = block {
                    p["songStage"] = runner.drill != nil ? "fixBar" : (runner.songResult != nil ? "results" : runner.song.current.title)
                }
            }
        }
        return p
    }
}
#endif
