import Foundation

/// How a learner's first minutes went, for the beta's "first note in under 3 minutes" goal
/// (docs/design/beginner-journeys.md, B0). Each moment is written once and never replaced.
public struct LearnerMetrics: Codable, Equatable, Sendable {
    /// Setup (onboarding) opened.
    public var setupStarted: Date?
    /// Setup finished and the learner was created.
    public var setupFinished: Date?
    /// The first note played on a lesson page.
    public var firstLessonNote: Date?
    /// The app's launch before that first note.
    public var launchBeforeFirstNote: Date?

    public init(setupStarted: Date? = nil, setupFinished: Date? = nil, firstLessonNote: Date? = nil,
                launchBeforeFirstNote: Date? = nil) {
        self.setupStarted = setupStarted
        self.setupFinished = setupFinished
        self.firstLessonNote = firstLessonNote
        self.launchBeforeFirstNote = launchBeforeFirstNote
    }

    /// Seconds from opening setup to the first lesson note.
    public var secondsFromSetupToFirstNote: Double? {
        guard let start = setupStarted, let note = firstLessonNote else { return nil }
        return note.timeIntervalSince(start)
    }

    /// Seconds from launching the app to the first lesson note.
    public var secondsFromLaunchToFirstNote: Double? {
        guard let launch = launchBeforeFirstNote, let note = firstLessonNote else { return nil }
        return note.timeIntervalSince(launch)
    }
}

/// `<learner folder>/metrics.json`. Kept by "Reset progress" (it describes setup, not progress).
extension LearnerHistory {
    var metricsURL: URL { folder.appendingPathComponent("metrics.json") }

    /// Missing or unreadable → empty.
    public func metrics() -> LearnerMetrics {
        guard let data = try? Data(contentsOf: metricsURL),
              let m = try? Self.jsonDecoder().decode(LearnerMetrics.self, from: data) else { return LearnerMetrics() }
        return m
    }

    /// Records setup's start and finish (only if not already recorded).
    public func recordSetup(started: Date, finished: Date) throws {
        var m = metrics()
        guard m.setupFinished == nil else { return }
        m.setupStarted = m.setupStarted ?? started
        m.setupFinished = finished
        try writeMetrics(m)
    }

    /// Records the first lesson note (only the first time). Returns true when it was recorded.
    @discardableResult
    public func recordFirstLessonNote(at date: Date = Date(), appLaunched: Date) throws -> Bool {
        var m = metrics()
        guard m.firstLessonNote == nil else { return false }
        m.firstLessonNote = date
        m.launchBeforeFirstNote = appLaunched
        try writeMetrics(m)
        return true
    }

    private func writeMetrics(_ m: LearnerMetrics) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(m).write(to: metricsURL, options: .atomic)
    }
}
