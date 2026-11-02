import Foundation

/// Drops microphone detections that are likely not keys the player struck, before they're
/// graded. Three kinds:
///
/// - **Spill:** a strike that sounded an expected key also lifts its neighbours and partials,
///   and some of them pass the detector's thresholds. An unexpected key from the same strike
///   that rose much less than the expected one is that spill, not a second key.
/// - **Weak strikes:** an unexpected key that barely rose above the room's noise. A strike's
///   strongest key always has `confidence` 1, so a stray one can only be told by `strength`.
/// - **Late:** an unexpected key the detector held for its sustain check whose pitch has
///   become expected meanwhile (the guide moved on). It was struck before its chord was due,
///   so it mustn't count as playing it.
///
/// Expected keys are always kept. The off event of a dropped key is dropped too.
public struct StrikeFilter: Sendable {
    public struct Settings: Sendable {
        /// An unexpected key is spill when it rose less than this share of the strongest
        /// expected key of the same strike.
        public var spillRatio: Double = 0.7
        /// An unexpected key needs at least this `strength` (rise over the room's noise).
        /// Off: on real takes, stray keys were no weaker than played ones.
        public var minimumStrength: Double = 0
        public init() {}
    }

    public enum Verdict: Equatable, Sendable { case keep, spill, weak, late }

    public var settings: Settings
    /// Keys whose on event was dropped: their next off is dropped too.
    private var dropped: Set<Int> = []
    /// The strongest expected key's confidence in recent strikes, for keys of those strikes
    /// that the detector reports later (after its sustain check).
    private var strikeExpected: [(strike: Int, confidence: Double)] = []

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Why an on event would be dropped (or `.keep`).
    /// - Parameter expectedRise: the confidence of the strongest expected key of its strike
    ///   (nil: none was heard).
    public func verdict(for note: DetectedNote, expectedRise: Double?, expected: Set<Int>) -> Verdict {
        guard note.kind == .on else { return .keep }
        let held = note.sustain != nil
        if held && expected.contains(note.pitch) { return .late }
        guard !expected.contains(note.pitch) else { return .keep }
        if let expectedRise, note.confidence < settings.spillRatio * expectedRise { return .spill }
        if note.strength < settings.minimumStrength { return .weak }
        return .keep
    }

    /// Filters one batch of detector events (in order). Each dropped on event is passed to
    /// `onDrop` with its reason.
    public mutating func filter(_ events: [DetectedNote], expected: Set<Int>,
                                onDrop: (DetectedNote, Verdict) -> Void = { _, _ in }) -> [DetectedNote] {
        for e in events where e.kind == .on && e.sustain == nil && expected.contains(e.pitch) {
            if let i = strikeExpected.firstIndex(where: { $0.strike == e.strike }) {
                strikeExpected[i].confidence = max(strikeExpected[i].confidence, e.confidence)
            } else {
                strikeExpected.append((e.strike, e.confidence))
                if strikeExpected.count > 8 { strikeExpected.removeFirst() }
            }
        }
        var kept: [DetectedNote] = []
        for e in events {
            switch e.kind {
            case .off:
                if dropped.remove(e.pitch) == nil { kept.append(e) }
            case .on:
                let rise = strikeExpected.first { $0.strike == e.strike }?.confidence
                let v = verdict(for: e, expectedRise: rise, expected: expected)
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

    /// Forgets dropped keys and recent strikes (when the detector is reset).
    public mutating func reset() {
        dropped = []
        strikeExpected = []
    }
}
