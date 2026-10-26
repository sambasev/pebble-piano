#if canImport(AVFoundation)
import AVFoundation
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
}
#endif
