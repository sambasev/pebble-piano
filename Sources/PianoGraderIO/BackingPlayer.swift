#if canImport(AVFoundation)
import AVFoundation
import Foundation
import PianoGraderCore

public enum BackingPlayerError: Error, CustomStringConvertible {
    case file(URL, Error)
    case engine(Error)

    public var description: String {
        switch self {
        case let .file(url, error): return "Couldn't open the backing track \(url.lastPathComponent): \(error.localizedDescription)"
        case let .engine(error): return "Couldn't start audio playback: \(error.localizedDescription)"
        }
    }
}

/// Plays a backing recording at an adjustable tempo, from the start of any bar, with a
/// count-in and an optional metronome. With no file it plays clicks only.
///
/// The recording goes through Apple's time-pitch unit, so slowing it down keeps its pitch
/// (and `transposeSemitones` changes pitch without changing speed).
///
/// Realtime safety: none of this class's code runs on an audio thread. Everything is
/// scheduled ahead from the calling thread (the main thread): the file segment on one
/// `AVAudioPlayerNode`, pre-rendered click buffers at exact host times on another. The render
/// thread only runs Apple's nodes, and no completion handlers are registered, so nothing of
/// ours is ever called back from it. Positions are worked out from the host clock instead
/// of being read from the render thread.
public final class BackingPlayer {
    public private(set) var clock: BeatClock
    public let fileURL: URL?
    /// Playback never starts before this time in the file (seconds)…
    public var trimStart: Double = 0
    /// …and stops here (nil: the end of the file).
    public var trimEnd: Double?
    /// Bars of clicks before the music starts.
    public var countInBars: Int
    /// Click on every beat while playing (applies from the next `play`).
    public var metronomeOn = false
    public var volume: Float = 0.9 { didSet { backingNode.volume = volume } }
    public var clickVolume: Float = 0.6 { didSet { clickNode.volume = clickVolume } }
    /// Shift the recording's pitch in semitones without changing its speed.
    public var transposeSemitones: Int = 0 { didSet { timePitch.pitch = Float(transposeSemitones * 100) } }
    /// Called on the main queue if playback had to stop (for example the output device changed).
    public var onInterrupted: (() -> Void)?

    public private(set) var isPlaying = false
    /// Where the music is, while playing: maps the uptime clock to quarters.
    public private(set) var anchor: PlaybackAnchor?

    private let engine = AVAudioEngine()
    private let backingNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let clickNode = AVAudioPlayerNode()
    private let file: AVAudioFile?
    private var click: AVAudioPCMBuffer?
    private var accent: AVAudioPCMBuffer?
    private var configObserver: NSObjectProtocol?

    /// Time allowed between scheduling and the first sound, so the engine has it in time.
    private static let scheduleLead = 0.12
    /// Most clicks scheduled in one go (a long piece with the metronome on).
    private static let maxClicks = 4000

    /// - Parameters:
    ///   - fileURL: the recording, or nil for clicks only.
    ///   - clock: where beat 0 is in the recording, its tempo and bars.
    public convenience init(annotation: BackingAnnotation, fileURL: URL?, clock: BeatClock,
                            outputDeviceUID: String? = nil) throws {
        try self.init(fileURL: fileURL, clock: clock, countInBars: annotation.countInBars ?? 1,
                      outputDeviceUID: outputDeviceUID)
        trimStart = max(0, annotation.trimStartSeconds ?? 0)
        trimEnd = annotation.trimEndSeconds
    }

    /// - Parameter outputDeviceUID: where to play (an `AudioDeviceInfo.uid`); nil: the system default.
    public init(fileURL: URL?, clock: BeatClock, countInBars: Int = 1, outputDeviceUID: String? = nil) throws {
        self.fileURL = fileURL
        self.clock = clock
        self.countInBars = max(0, countInBars)
        if let fileURL {
            do { file = try AVAudioFile(forReading: fileURL) } catch { throw BackingPlayerError.file(fileURL, error) }
        } else {
            file = nil
        }

        #if os(macOS)
        // Before reading the output's sample rate: it's the chosen device's.
        if let outputDeviceUID { AudioDevices.setOutput(of: engine, toUID: outputDeviceUID) }
        #endif
        let mixer = engine.mainMixerNode
        if let file {
            engine.attach(backingNode)
            engine.attach(timePitch)
            engine.connect(backingNode, to: timePitch, format: file.processingFormat)
            engine.connect(timePitch, to: mixer, format: file.processingFormat)
            backingNode.volume = volume
        }
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = 48000 }
        if let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) {
            engine.attach(clickNode)
            engine.connect(clickNode, to: mixer, format: format)
            clickNode.volume = clickVolume
            click = Self.makeClick(format: format, frequency: 1000, gain: 0.5)
            accent = Self.makeClick(format: format, frequency: 1500, gain: 0.7)
        }
        engine.prepare()
        do { try engine.start() } catch { throw BackingPlayerError.engine(error) }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let wasPlaying = self.isPlaying
            self.stop()
            try? self.engine.start()
            if wasPlaying { self.onInterrupted?() }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        stop()
        engine.stop()
    }

    /// Length of the audio file in seconds (nil without a file).
    public var fileDuration: Double? {
        guard let file else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Where playback stops, in seconds of the file.
    private var playEndSeconds: Double? {
        guard let d = fileDuration else { return nil }
        return min(d, trimEnd ?? d)
    }

    /// Length of the recording in quarters from beat 0, to the trim end (nil without a file).
    public var lengthInQuarters: Double? {
        playEndSeconds.map { clock.quarter(atAudioSeconds: $0) }
    }

    /// Schedules the file from `start` to the trim end, to begin sounding at `uptime`.
    /// Returns false if there's nothing left to play.
    @discardableResult
    private func scheduleFile(from start: Double, at uptime: Double) -> Bool {
        guard let file, let end = playEndSeconds else { return false }
        let rate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * rate)
        let endFrame = min(file.length, AVAudioFramePosition(end * rate))
        guard startFrame < endFrame else { return false }
        backingNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(endFrame - startFrame),
                                    at: nil, completionHandler: nil)
        backingNode.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: uptime)))
        return true
    }

    /// Plays from any point of the file (seconds) with no count-in, for checking markers by ear.
    /// With `clicks`, the metronome sounds on every beat from bar 1's grid. Returns an anchor.
    @discardableResult
    public func play(fromAudioSeconds seconds: Double, clicks: Bool) -> PlaybackAnchor {
        stop()
        if !engine.isRunning { try? engine.start() }
        timePitch.rate = Float(clock.tempoFactor)
        let start = max(trimStart, seconds)
        let begin = AVAudioTime.seconds(forHostTime: mach_absolute_time()) + Self.scheduleLead
        scheduleFile(from: start, at: begin)
        let spq = clock.secondsPerQuarter
        let startQuarter = clock.quarter(atAudioSeconds: start)
        if clicks, let click, let accent {
            let qpb = clock.timeSignature.quartersPerBeat
            let end = lengthInQuarters ?? (startQuarter + 64 * clock.quartersPerBar)
            // Beats on bar 1's grid (bar 1 at quarter 0), including bars before it.
            var beat = Int((startQuarter / qpb).rounded(.up))
            var scheduled = 0
            while Double(beat) * qpb < end, scheduled < Self.maxClicks {
                let q = Double(beat) * qpb
                let beatsPerBar = max(1, clock.timeSignature.numerator)
                let isDownbeat = ((beat % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
                schedule(isDownbeat ? accent : click, at: begin + (q - startQuarter) * spq)
                scheduled += 1
                beat += 1
            }
            if scheduled > 0 { clickNode.play() }
        }
        let anchor = PlaybackAnchor(uptime: begin + engine.outputNode.presentationLatency,
                                    quarter: startQuarter, secondsPerQuarter: spq)
        self.anchor = anchor
        isPlaying = true
        return anchor
    }

    /// Whether bar `bar` (0-based, played order) is wholly inside the trimmed recording, so it
    /// can be played as a lead-in. False with no recording.
    public func hasAudio(forBar bar: Int) -> Bool {
        guard bar >= 0, file != nil, let end = playEndSeconds else { return false }
        let start = clock.audioSeconds(atQuarter: clock.barStart(bar))
        let stop = clock.audioSeconds(atQuarter: clock.barStart(bar + 1))
        return start >= trimStart - 0.02 && stop <= end + 0.02
    }

    /// Changes the speed; takes effect at the next `play`.
    public func setTempoFactor(_ factor: Double) {
        clock.tempoFactor = max(0.25, min(2, factor))
    }

    /// Stops, then plays from the start of `bar` (0-based, played order) after `countIn` bars
    /// of clicks. From bar 0 the recording's intro (before beat 0) plays too, ending on the
    /// downbeat. Returns where the music is, against the uptime clock.
    ///
    /// - Parameter until: where to stop clicking for the metronome (defaults to the end of
    ///   the recording, or 64 bars with no recording).
    @discardableResult
    public func play(fromBar bar: Int, countIn: Int? = nil, until endQuarter: Double? = nil,
                     includeIntro: Bool = true) -> PlaybackAnchor {
        stop()
        if !engine.isRunning { try? engine.start() }
        let bars = max(0, countIn ?? countInBars)
        let barQuarter = clock.barStart(bar)
        let secondsPerQuarter = clock.secondsPerQuarter
        timePitch.rate = Float(clock.tempoFactor)

        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        var clickStart = now + Self.scheduleLead
        var barTime = clickStart + Double(bars) * clock.quartersPerBar * secondsPerQuarter

        // The recording. From the first bar, the intro (from the trim start) can play too.
        // The file is scheduled so the bar's audio lands exactly at `barTime`: an intro starts
        // earlier, and a bar that begins before the trim start comes in partway through.
        if file != nil {
            let barAudio = clock.audioSeconds(atQuarter: barQuarter)
            let segmentStart = bar == 0 && includeIntro ? min(trimStart, barAudio) : max(trimStart, barAudio)
            let offset = (segmentStart - barAudio) / clock.tempoFactor
            if barTime + offset < clickStart {
                let shift = clickStart - (barTime + offset)
                clickStart += shift
                barTime += shift
            }
            scheduleFile(from: segmentStart, at: barTime + offset)
        }

        // Count-in and metronome clicks, on the beat (the time signature's denominator).
        if let click, let accent {
            let beatSeconds = clock.timeSignature.quartersPerBeat * secondsPerQuarter
            let beatsPerBar = max(1, clock.timeSignature.numerator)
            var scheduled = 0
            for i in 0..<(bars * beatsPerBar) {
                schedule(i % beatsPerBar == 0 ? accent : click, at: clickStart + Double(i) * beatSeconds)
                scheduled += 1
            }
            if metronomeOn {
                let end = endQuarter ?? lengthInQuarters ?? (barQuarter + 64 * clock.quartersPerBar)
                var b = bar
                outer: while clock.barStart(b) < end {
                    let start = clock.barStart(b)
                    let beats = Int((clock.barLength(b) / clock.timeSignature.quartersPerBeat).rounded())
                    for k in 0..<max(1, beats) {
                        let q = start + Double(k) * clock.timeSignature.quartersPerBeat
                        guard q < end, scheduled < Self.maxClicks else { break outer }
                        schedule(k == 0 ? accent : click, at: barTime + (q - barQuarter) * secondsPerQuarter)
                        scheduled += 1
                    }
                    b += 1
                }
            }
            if scheduled > 0 { clickNode.play() }
        }

        // Output latency: the bar is heard a little after it is rendered.
        let heard = barTime + engine.outputNode.presentationLatency
        let anchor = PlaybackAnchor(uptime: heard, quarter: barQuarter, secondsPerQuarter: secondsPerQuarter)
        self.anchor = anchor
        isPlaying = true
        return anchor
    }

    /// Stops the recording and any clicks still to come.
    public func stop() {
        // Only nodes attached to the engine can be stopped.
        if file != nil { backingNode.stop() }
        if click != nil { clickNode.stop() }
        isPlaying = false
        anchor = nil
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, at uptime: Double) {
        let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: uptime))
        clickNode.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
    }

    /// A short decaying sine "tick".
    private static func makeClick(format: AVAudioFormat, frequency: Double, gain: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * 0.04)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            let value = Float(sin(2 * Double.pi * frequency * t) * exp(-t * 90)) * gain
            for c in 0..<Int(format.channelCount) { channels[c][i] = value }
        }
        return buffer
    }
}
#endif
