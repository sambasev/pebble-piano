import Foundation

/// Drops microphone detections that are likely not keys the player struck, before they're
/// graded. Two kinds:
///
/// - **Spill:** a strike that sounded an expected key also lifts its neighbours and partials,
///   and some of them pass the detector's thresholds. An unexpected key from the same strike
///   that rose much less than the expected one is that spill, not a second key.
/// - **Weak strikes:** an unexpected key that barely rose above the room's noise. A strike's
///   strongest key always has `confidence` 1, so a stray one can only be told by `strength`.
///
/// Expected keys are always kept. The off event of a dropped key is dropped too.
public struct StrikeFilter: Sendable {
    public struct Settings: Sendable {
        /// An unexpected key is spill when it rose less than this share of the strongest
        /// expected key of the same strike.
        public var spillRatio: Double = 0.7
        /// An unexpected key needs at least this `strength` (rise over the room's noise).
        public var minimumStrength: Double = 0
        public init() {}
    }

    public enum Verdict: Equatable, Sendable { case keep, spill, weak }

    public var settings: Settings
    /// Keys whose on event was dropped: their next off is dropped too.
    private var dropped: Set<Int> = []

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Why an on event would be dropped (or `.keep`), given the other notes of its strike.
    public func verdict(for note: DetectedNote, among strike: [DetectedNote], expected: Set<Int>) -> Verdict {
        guard note.kind == .on, !expected.contains(note.pitch) else { return .keep }
        let expectedRise = strike.filter { $0.kind == .on && expected.contains($0.pitch) }.map(\.confidence).max()
        if let expectedRise, note.confidence < settings.spillRatio * expectedRise { return .spill }
        if note.strength < settings.minimumStrength { return .weak }
        return .keep
    }

    /// Filters one batch of detector events (in order). Each dropped on event is passed to
    /// `onDrop` with its reason.
    public mutating func filter(_ events: [DetectedNote], expected: Set<Int>,
                                onDrop: (DetectedNote, Verdict) -> Void = { _, _ in }) -> [DetectedNote] {
        var kept: [DetectedNote] = []
        for e in events {
            switch e.kind {
            case .off:
                if dropped.remove(e.pitch) == nil { kept.append(e) }
            case .on:
                let strike = events.filter { $0.kind == .on && $0.strike == e.strike }
                let v = verdict(for: e, among: strike, expected: expected)
                if v == .keep {
                    dropped.remove(e.pitch)
                    kept.append(e)
                } else {
                    dropped.insert(e.pitch)
                    onDrop(e, v)
                }
            }
        }
        return kept
    }

    /// Forgets dropped keys (when the detector is reset).
    public mutating func reset() { dropped = [] }
}
