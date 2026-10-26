import Foundation

/// Play-along mode: the music keeps moving and the judge decides whether the player is
/// keeping up well enough to carry on, or whether to stop and replay the current bar.
///
/// - A chord is **hit** when enough of its notes (`minChordCoverage`) are struck within
///   `earlySeconds` before to `lateSeconds` after its time. Each struck key goes to the
///   nearest open chord that contains it, so repeated notes are matched one by one.
/// - A chord is **missed** once its late window has passed without being hit.
/// - Wrong keys never stop the music; they are only counted (`extraNotes`).
/// - A bar **fails** when its misses exceed `min(maxMissesPerBar, ⌊chords × maxMissFraction⌋)`,
///   or when `maxConsecutiveMisses` chords in a row are missed (the player stopped). Then the
///   verdict is `.rewind(bar:)`: the bar where the trouble started.
///
/// The judge works in quarter notes from the reference's beat 0 (the `BeatClock` timeline).
/// After `init`, nothing allocates: every array is sized up front and pitch sets are bit
/// masks, so it can run on any thread, including a realtime one.
public struct PlayAlongJudge: Sendable {
    public struct Settings: Equatable, Sendable {
        public var earlySeconds: Double = 0.25
        public var lateSeconds: Double = 0.40
        public var maxMissFraction: Double = 0.34
        public var maxMissesPerBar: Int = 2
        public var maxConsecutiveMisses: Int = 3
        /// Share of a chord's notes that must be struck (at least one note).
        public var minChordCoverage: Double = 0.5

        public init() {}
    }

    public enum Verdict: Equatable, Sendable {
        case onTrack
        /// Stop and play again from the start of this bar (0-based, played order).
        case rewind(bar: Int)
        /// Every chord is resolved and the end of the last bar has passed.
        case finished
    }

    public enum ChordState: UInt8, Sendable {
        case pending, hit, missed
    }

    public let chordQuarters: [Double]
    public let chordPitches: [PitchSet]
    /// Bar of each chord (0-based, played order).
    public let chordBars: [Int]
    public let barCount: Int
    /// End of the last bar that has a chord.
    public let endQuarter: Double

    public private(set) var settings: Settings
    public private(set) var secondsPerQuarter: Double
    private var earlyQuarters: Double
    private var lateQuarters: Double
    private var required: [Int]

    public private(set) var states: [ChordState]
    /// Keys struck for each chord in the current attempt.
    public private(set) var struck: [PitchSet]
    public private(set) var barMisses: [Int]
    private let barChordCount: [Int]
    /// First chord not yet resolved (in order).
    private var cursor = 0
    private var consecutiveMisses = 0
    private var runStartBar = 0
    /// Bar the current attempt started from.
    public private(set) var startBar = 0
    /// Keys struck that matched no open chord.
    public private(set) var extraNotes = 0
    public private(set) var isFinished = false
    /// The chord most recently marked missed (the one that tipped a bar over, on `.rewind`).
    public private(set) var lastMissedChord: Int?

    /// - Parameters:
    ///   - chords: (time in quarters, pitches) of each chord the player plays. Kept in the
    ///     given order when already sorted, so indices match the caller's chord list.
    ///   - clock: bar layout, and the tempo the windows are converted with.
    public init(chords: [(quarter: Double, pitches: Set<Int>)], clock: BeatClock, settings: Settings = Settings()) {
        let sorted = chords.filter { !$0.pitches.isEmpty }.enumerated()
            .sorted { ($0.element.quarter, $0.offset) < ($1.element.quarter, $1.offset) } // stable
            .map { $0.element }
        chordQuarters = sorted.map { $0.quarter }
        chordPitches = sorted.map { PitchSet($0.pitches) }
        chordBars = sorted.map { clock.barIndex(containing: $0.quarter) }
        let bars = (chordBars.max() ?? -1) + 1
        barCount = bars
        endQuarter = bars > 0 ? clock.barStart(bars) : 0
        var perBar = [Int](repeating: 0, count: max(bars, 1))
        for b in chordBars { perBar[b] += 1 }
        barChordCount = perBar
        barMisses = [Int](repeating: 0, count: max(bars, 1))
        states = [ChordState](repeating: .pending, count: sorted.count)
        struck = [PitchSet](repeating: PitchSet(), count: sorted.count)
        required = [Int](repeating: 1, count: sorted.count)
        self.settings = settings
        secondsPerQuarter = clock.secondsPerQuarter
        earlyQuarters = 0
        lateQuarters = 0
        configure(settings: settings, secondsPerQuarter: clock.secondsPerQuarter)
    }

    public init(chords: [ChordEvent], clock: BeatClock, settings: Settings = Settings()) {
        self.init(chords: chords.map { (quarter: $0.onsetBeats, pitches: $0.pitches) }, clock: clock, settings: settings)
    }

    public var chordCount: Int { chordQuarters.count }

    /// New windows or a new tempo. Takes effect for chords not yet resolved.
    public mutating func configure(settings: Settings, secondsPerQuarter: Double) {
        self.settings = settings
        self.secondsPerQuarter = max(1e-6, secondsPerQuarter)
        earlyQuarters = max(0, settings.earlySeconds) / self.secondsPerQuarter
        lateQuarters = max(0, settings.lateSeconds) / self.secondsPerQuarter
        let coverage = min(1, max(0, settings.minChordCoverage))
        for i in 0..<chordPitches.count {
            let n = chordPitches[i].count
            required[i] = min(n, max(1, Int((Double(n) * coverage).rounded(.up))))
        }
    }

    // MARK: Input

    /// A key went down at `quarter` (already corrected for input latency). Returns whether it
    /// matched an open chord (false: a wrong or stray key, counted in `extraNotes`).
    @discardableResult
    public mutating func noteOn(_ pitch: Int, atQuarter quarter: Double) -> Bool {
        guard !isFinished else { return false }
        var best = -1
        var bestDistance = Double.infinity
        var i = cursor
        while i < chordQuarters.count {
            let cq = chordQuarters[i]
            if cq - earlyQuarters > quarter { break }
            if states[i] != .missed, cq + lateQuarters >= quarter,
               chordPitches[i].contains(pitch), !struck[i].contains(pitch) {
                let d = abs(quarter - cq)
                if d < bestDistance { best = i; bestDistance = d }
            }
            i += 1
        }
        guard best >= 0 else {
            extraNotes += 1
            return false
        }
        struck[best].insert(pitch)
        if states[best] == .pending, struck[best].count >= required[best] {
            states[best] = .hit
        }
        return true
    }

    // MARK: Time

    /// The music has reached `quarter`: close chords whose late window has passed.
    public mutating func advance(toQuarter quarter: Double) -> Verdict {
        guard !isFinished else { return .finished }
        while cursor < chordQuarters.count {
            switch states[cursor] {
            case .pending:
                guard chordQuarters[cursor] + lateQuarters < quarter else { return .onTrack }
                states[cursor] = .missed
                lastMissedChord = cursor
                let bar = chordBars[cursor]
                if consecutiveMisses == 0 { runStartBar = bar }
                consecutiveMisses += 1
                barMisses[bar] += 1
                cursor += 1
                if consecutiveMisses >= max(1, settings.maxConsecutiveMisses) { return .rewind(bar: runStartBar) }
                if barFailed(bar) { return .rewind(bar: bar) }
            case .hit:
                consecutiveMisses = 0
                cursor += 1
            case .missed:
                cursor += 1
            }
        }
        if quarter >= endQuarter {
            isFinished = true
            return .finished
        }
        return .onTrack
    }

    /// Misses allowed in a bar before it fails.
    public func allowedMisses(inBar bar: Int) -> Int {
        guard bar >= 0, bar < barChordCount.count else { return 0 }
        let byShare = Int((Double(barChordCount[bar]) * max(0, settings.maxMissFraction)).rounded(.down))
        return min(max(0, settings.maxMissesPerBar), byShare)
    }

    private func barFailed(_ bar: Int) -> Bool { barMisses[bar] > allowedMisses(inBar: bar) }

    /// Misses so far in a bar, and how many it may have before it is replayed.
    public func misses(inBar bar: Int) -> (count: Int, allowed: Int) {
        guard bar >= 0, bar < barMisses.count else { return (0, 0) }
        return (barMisses[bar], allowedMisses(inBar: bar))
    }

    // MARK: Attempts

    /// Starts a new attempt at bar `bar`: that bar and everything after it is forgotten.
    public mutating func rewind(toBar bar: Int) {
        let b = min(max(0, bar), max(0, barCount - 1))
        startBar = b
        var first = chordQuarters.count
        for i in 0..<chordQuarters.count where chordBars[i] >= b {
            if i < first { first = i }
            states[i] = .pending
            struck[i] = PitchSet()
        }
        for i in b..<barMisses.count { barMisses[i] = 0 }
        cursor = first
        consecutiveMisses = 0
        runStartBar = b
        isFinished = false
    }

    /// Wait-for-the-note mode: the music has stopped on chord `index`. It is open again (its
    /// time window no longer applies; play it with `noteOn(_:atQuarter:)` at its own time),
    /// its miss is taken back, and judging carries on from it once it is played.
    public mutating func waitOn(chord index: Int) {
        guard index >= 0, index < chordQuarters.count else { return }
        if states[index] == .missed {
            let bar = chordBars[index]
            barMisses[bar] = max(0, barMisses[bar] - 1)
        }
        states[index] = .pending
        struck[index] = PitchSet()
        cursor = index
        consecutiveMisses = 0
        isFinished = false
    }

    /// Back to the beginning with nothing played.
    public mutating func reset() {
        rewind(toBar: 0)
        for i in 0..<states.count {
            states[i] = .pending
            struck[i] = PitchSet()
        }
        for i in 0..<barMisses.count { barMisses[i] = 0 }
        extraNotes = 0
    }

    // MARK: Display

    /// The next chord still to be played, if any (index into the chord arrays).
    public var nextChordIndex: Int? {
        var i = cursor
        while i < states.count {
            if states[i] == .pending { return i }
            i += 1
        }
        return nil
    }

    /// Notes of the next chord not yet struck.
    public var expected: PitchSet {
        guard let i = nextChordIndex else { return PitchSet() }
        return chordPitches[i].subtracting(struck[i])
    }
}
