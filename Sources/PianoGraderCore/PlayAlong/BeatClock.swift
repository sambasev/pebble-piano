import Foundation

/// Musical time for playing along with a recording.
///
/// Positions are in quarter notes from the reference MIDI's beat 0, the same units as
/// `NoteEvent.onsetBeats`, so the judge, the playhead and the audio share one timeline.
/// Bars are counted from 0 in played order (repeats written out, as in the reference).
///
/// All methods are allocation-free.
public struct BeatClock: Equatable, Sendable {
    /// Where beat 0 falls in the audio, in seconds of the recording.
    public var startSeconds: Double
    /// Tempo of the recording, in quarter notes per minute.
    public var bpm: Double
    public var timeSignature: TimeSignature
    /// Playback speed: 1 as recorded, 0.75 for three-quarter speed.
    public var tempoFactor: Double
    /// Start of each listed bar in quarters (bar 0 starts at 0). Bars after the list
    /// continue at the time signature's length.
    public private(set) var barStarts: [Double]
    /// Where the listed bars end.
    private var listedEnd: Double

    /// - Parameter barLengths: length of each bar in quarters, in played order, when they
    ///   differ from the time signature (a pickup bar). Empty: every bar is a full one.
    public init(startSeconds: Double = 0, bpm: Double, timeSignature: TimeSignature = .common,
                barLengths: [Double] = [], tempoFactor: Double = 1) {
        self.startSeconds = startSeconds
        self.bpm = max(1, bpm)
        self.timeSignature = timeSignature
        self.tempoFactor = max(0.05, tempoFactor)
        var starts: [Double] = []
        var position = 0.0
        for length in barLengths where length > 0 {
            starts.append(position)
            position += length
        }
        barStarts = starts
        listedEnd = position
    }

    public var quartersPerBar: Double { timeSignature.quartersPerMeasure }

    /// Real seconds one quarter note lasts at the current tempo factor.
    public var secondsPerQuarter: Double { 60 / (bpm * tempoFactor) }

    /// Time in the recording (seconds) of a position.
    public func audioSeconds(atQuarter quarter: Double) -> Double { startSeconds + quarter * 60 / bpm }

    /// Position at a time in the recording.
    public func quarter(atAudioSeconds seconds: Double) -> Double { (seconds - startSeconds) * bpm / 60 }

    /// The bar a position falls in (0 for anything before the start).
    public func barIndex(containing quarter: Double) -> Int {
        let q = quarter + 1e-6
        guard q > 0 else { return 0 }
        if q >= listedEnd {
            let past = Int(((q - listedEnd) / quartersPerBar).rounded(.down))
            return barStarts.count + past
        }
        // Last listed bar starting at or before q.
        var low = 0, high = barStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if barStarts[mid] <= q { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Where bar `index` starts, in quarters.
    public func barStart(_ index: Int) -> Double {
        let i = max(0, index)
        if i < barStarts.count { return barStarts[i] }
        return listedEnd + Double(i - barStarts.count) * quartersPerBar
    }

    /// Length of bar `index` in quarters.
    public func barLength(_ index: Int) -> Double { barStart(index + 1) - barStart(index) }
}

/// Ties the musical timeline to the system uptime clock (the clock MIDI, key and microphone
/// events are stamped with): at `uptime` the player hears `quarter`.
public struct PlaybackAnchor: Equatable, Sendable {
    public var uptime: Double
    public var quarter: Double
    /// Real seconds per quarter note while this anchor holds.
    public var secondsPerQuarter: Double

    public init(uptime: Double, quarter: Double, secondsPerQuarter: Double) {
        self.uptime = uptime
        self.quarter = quarter
        self.secondsPerQuarter = max(1e-6, secondsPerQuarter)
    }

    public func quarter(atUptime time: Double) -> Double { quarter + (time - uptime) / secondsPerQuarter }

    public func uptime(atQuarter q: Double) -> Double { uptime + (q - quarter) * secondsPerQuarter }
}
