import Foundation

/// Wait mode: the playhead holds on each chord of the reference until it is played cleanly.
///
/// A chord counts when all of its notes have been struck and no wrong key is down. Striking a
/// key that isn't in the chord cancels the attempt: the chord's notes must be played again
/// (so D+E doesn't pass for D). Keys still held from an earlier chord don't count against the
/// player, so legato playing works.
///
/// Keys meant to sound together arrive a few milliseconds apart, so the guide only moves on
/// once the chord has stayed clean for `settleWindow` seconds. `noteOn` returns the time to
/// call `settle(at:)`; until then a late wrong key still cancels the attempt.
public struct WaitGuide: Sendable {
    public let chords: [Set<Int>]
    public var settleWindow: Double

    /// Index of the chord being waited for (== chords.count when finished).
    public private(set) var index = 0
    /// Notes of the current chord struck in this attempt.
    public private(set) var hit: Set<Int> = []
    /// Keys held that the guide did not expect when they were struck.
    public private(set) var wrongHeld: Set<Int> = []
    /// Wrong keys held that stop the chord from passing (struck strictly).
    private var blockingWrong: Set<Int> = []
    /// When the current chord was last completed cleanly, if an advance is pending.
    private var completedAt: Double?

    public init(chords: [Set<Int>], settleWindow: Double = 0.05) {
        self.chords = chords.filter { !$0.isEmpty }
        self.settleWindow = max(0, settleWindow)
    }

    public var isFinished: Bool { index >= chords.count }

    /// Notes still to play for the current chord.
    public var expected: Set<Int> { isFinished ? [] : chords[index].subtracting(hit) }

    /// A key went down. Returns the time to call `settle(at:)` when the chord is now complete.
    /// - Parameter strict: whether a key outside the chord cancels the attempt. Pass false for
    ///   input that can hear keys that weren't played (a microphone): the extra key is still
    ///   reported in `wrongHeld`, but the chord can pass once all its notes are heard.
    @discardableResult
    public mutating func noteOn(_ pitch: Int, at time: Double, strict: Bool = true) -> Double? {
        guard !isFinished else { return nil }
        let chord = chords[index]
        guard chord.contains(pitch) else {
            wrongHeld.insert(pitch)
            if strict {
                // A wrong key cancels the attempt: the chord has to be played again, cleanly.
                blockingWrong.insert(pitch)
                hit = []
                completedAt = nil
            }
            return nil
        }
        hit.insert(pitch)
        guard hit.isSuperset(of: chord), blockingWrong.isEmpty else { return nil }
        completedAt = time
        return time + settleWindow
    }

    /// A key came up. Releasing a wrong key never completes a chord by itself: the right
    /// notes must be struck again.
    public mutating func noteOff(_ pitch: Int) {
        wrongHeld.remove(pitch)
        blockingWrong.remove(pitch)
    }

    /// Moves on if the chord was completed at least `settleWindow` ago and has stayed clean.
    /// Returns true when the guide advanced.
    @discardableResult
    public mutating func settle(at time: Double) -> Bool {
        guard !isFinished, let completed = completedAt, time + 1e-9 >= completed + settleWindow,
              blockingWrong.isEmpty, hit.isSuperset(of: chords[index]) else { return false }
        index += 1
        hit = []
        completedAt = nil
        return true
    }

    /// Waits on chord `index` next, as if everything before it had been played.
    public mutating func jump(to index: Int) {
        reset()
        self.index = min(max(0, index), chords.count)
    }

    /// Back to the first chord.
    public mutating func reset() {
        index = 0
        hit = []
        wrongHeld = []
        blockingWrong = []
        completedAt = nil
    }
}
