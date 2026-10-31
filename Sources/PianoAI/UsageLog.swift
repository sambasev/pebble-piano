import Foundation

/// Every model call, with its latency and tokens, so the hackathon credits last.
/// Each call is also printed to the console with a `[PianoAI]` prefix.
public actor UsageLog {
    public static let shared = UsageLog()

    public struct Entry: Sendable, Equatable {
        public var date: Date
        public var provider: ModelProvider
        public var model: String
        public var operation: String
        public var seconds: Double
        public var inputTokens: Int?
        public var outputTokens: Int?
        /// Seconds of audio sent, for transcription (billed by audio time).
        public var audioSeconds: Double?
        public var error: String?
    }

    public private(set) var entries: [Entry] = []
    private let printsToConsole: Bool

    public init(printsToConsole: Bool = true) { self.printsToConsole = printsToConsole }

    public func record(_ entry: Entry) {
        entries.append(entry)
        guard printsToConsole else { return }
        var line = "[PianoAI] \(entry.provider.rawValue) \(entry.model) \(entry.operation) "
            + String(format: "%.2fs", entry.seconds)
        if let i = entry.inputTokens { line += " in=\(i)" }
        if let o = entry.outputTokens { line += " out=\(o)" }
        if let a = entry.audioSeconds { line += String(format: " audio=%.1fs", a) }
        if let e = entry.error { line += " ERROR \(e)" }
        print(line)
    }

    public struct Totals: Sendable, Equatable {
        public var calls = 0
        public var failures = 0
        public var inputTokens = 0
        public var outputTokens = 0
        public var audioSeconds = 0.0

        public init() {}
    }

    public func totals() -> Totals {
        var t = Totals()
        for e in entries {
            t.calls += 1
            if e.error != nil { t.failures += 1 }
            t.inputTokens += e.inputTokens ?? 0
            t.outputTokens += e.outputTokens ?? 0
            t.audioSeconds += e.audioSeconds ?? 0
        }
        return t
    }
}
