#if canImport(AVFoundation)
import AVFoundation
import AudioToolbox
import Foundation

/// Plays notes through Apple's built-in General MIDI piano.
public final class PianoSynth {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    /// - Parameter outputDeviceUID: where to play (an `AudioDeviceInfo.uid`); nil: the system
    ///   default output.
    public init?(outputDeviceUID: String? = nil) {
        #if os(macOS)
        if let outputDeviceUID { AudioDevices.setOutput(of: engine, toUID: outputDeviceUID) }
        #endif
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        if FileManager.default.fileExists(atPath: bank.path) {
            // Program 0 = Acoustic Grand Piano. Falls back to the sampler's default tone if loading fails.
            try? sampler.loadSoundBankInstrument(at: bank, program: 0, bankMSB: 0x79, bankLSB: 0)
        }
        do { try engine.start() } catch { return nil }
    }

    #if os(macOS)
    /// Plays through another output (nil: the system default).
    public func setOutputDevice(uid: String?) {
        AudioDevices.setOutput(of: engine, toUID: uid)
    }
    #endif

    /// Loudness as a linear factor: 1 as the instrument comes, up to 4 (+12 dB), 0 silent.
    public var volume: Double = 1 {
        didSet {
            let v = max(0, min(4, volume))
            sampler.overallGain = v <= 0.0001 ? -90 : Float(20 * log10(v))
        }
    }

    public func noteOn(pitch: Int, velocity: Int) {
        guard (0...127).contains(pitch) else { return }
        sampler.startNote(UInt8(pitch), withVelocity: UInt8(max(1, min(127, velocity))), onChannel: 0)
    }

    public func noteOff(pitch: Int) {
        guard (0...127).contains(pitch) else { return }
        sampler.stopNote(UInt8(pitch), onChannel: 0)
    }

    /// Plays a note for a fixed length.
    public func play(pitch: Int, velocity: Int, duration: Double) {
        noteOn(pitch: pitch, velocity: velocity)
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.noteOff(pitch: pitch)
        }
    }

    public func allNotesOff() {
        for pitch in 0...127 { sampler.stopNote(UInt8(pitch), onChannel: 0) }
    }

    // MARK: Sequences

    /// One note of a sequence: seconds from the sequence's start.
    public struct SequenceNote: Equatable, Sendable {
        public var pitch: Int
        public var velocity: Int
        public var start: Double
        public var end: Double

        public init(pitch: Int, velocity: Int, start: Double, end: Double) {
            self.pitch = pitch
            self.velocity = velocity
            self.start = start
            self.end = end
        }
    }

    private var sequencer: AVAudioSequencer?

    /// Plays a whole sequence on the audio engine's own clock, so every note lands on time
    /// however busy the main thread is (the UI redrawing can't delay it). Replaces any sequence
    /// already playing. Returns false if it couldn't start; the caller can fall back.
    @discardableResult
    public func playSequence(_ notes: [SequenceNote]) -> Bool {
        stopSequence()
        guard !notes.isEmpty, let data = Self.midiData(notes) else { return false }
        let player = AVAudioSequencer(audioEngine: engine)
        do {
            try player.load(from: data, options: [])
            for track in player.tracks { track.destinationAudioUnit = sampler }
            player.currentPositionInSeconds = 0
            player.prepareToPlay()
            if !engine.isRunning { try engine.start() }
            try player.start()
        } catch {
            return false
        }
        sequencer = player
        return true
    }

    /// Seconds into the sequence playing now; nil when none is.
    public var sequencePosition: Double? {
        guard let sequencer, sequencer.isPlaying else { return nil }
        return sequencer.currentPositionInSeconds
    }

    /// Stops the sequence and silences its notes.
    public func stopSequence() {
        guard let player = sequencer else { return }
        player.stop()
        sequencer = nil
        allNotesOff()
    }

    /// A one-track standard MIDI file at 60 bpm, so one beat is one second.
    static func midiData(_ notes: [SequenceNote]) -> Data? {
        var made: MusicSequence?
        guard NewMusicSequence(&made) == noErr, let sequence = made else { return nil }
        defer { DisposeMusicSequence(sequence) }
        var tempo: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempo) == noErr, let tempo {
            MusicTrackNewExtendedTempoEvent(tempo, 0, 60)
        }
        var newTrack: MusicTrack?
        guard MusicSequenceNewTrack(sequence, &newTrack) == noErr, let track = newTrack else { return nil }
        for n in notes where (0...127).contains(n.pitch) && n.end > n.start {
            var message = MIDINoteMessage(channel: 0, note: UInt8(n.pitch),
                                          velocity: UInt8(max(1, min(127, n.velocity))),
                                          releaseVelocity: 0, duration: Float32(n.end - n.start))
            MusicTrackNewMIDINoteEvent(track, MusicTimeStamp(max(0, n.start)), &message)
        }
        var out: Unmanaged<CFData>?
        guard MusicSequenceFileCreateData(sequence, .midiType, .eraseFile, 960, &out) == noErr, let out else { return nil }
        return out.takeRetainedValue() as Data
    }
}
#endif
