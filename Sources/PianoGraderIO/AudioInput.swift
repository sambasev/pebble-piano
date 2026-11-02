#if canImport(AVFoundation)
import AVFoundation
import Foundation
import PianoGraderCore
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

public enum AudioInputError: Error, CustomStringConvertible {
    case permissionDenied
    case noInput
    case engine(Error)

    public var description: String {
        switch self {
        case .permissionDenied: return "Microphone access was denied (System Settings → Privacy & Security → Microphone)."
        case .noInput: return "No microphone input is available."
        case .engine(let error): return "Couldn't start the microphone: \(error)."
        }
    }
}

/// Listens to the microphone and reports piano notes on the main queue, with low latency:
/// audio arrives in small buffers (256 frames asked for), the detector runs on its own queue,
/// and each note's time is when the key was struck, on the system uptime clock (the same
/// clock as MIDI input and key events).
///
/// Threads: the sink node's block runs on the audio I/O thread, which is realtime. It only
/// copies channel 0 into a preallocated lock-free ring and posts the block's length and host
/// time (`RealtimeEventQueue`): no allocation, locks, Objective-C messages, dispatch or
/// reference counting there. A worker thread drains the ring and hands each block to the
/// detector queue, where the analysis runs as before.
public final class AudioInput {
    public typealias NoteOn = (_ pitch: Int, _ time: Double) -> Void
    public typealias NoteOff = (_ pitch: Int, _ time: Double) -> Void

    private let engine = AVAudioEngine()
    private var sink: AVAudioSinkNode?
    private let queue = DispatchQueue(label: "PianoPad.audio-input", qos: .userInteractive)
    private var detector: PianoNoteDetector?
    /// Drops spill and weak strikes the detector reports (detector queue only).
    private var strikeFilter = StrikeFilter()
    private let onNoteOn: NoteOn
    private let onNoteOff: NoteOff
    private var pendingExpected: Set<Int> = []
    private var muted = false
    private var recorder: MicRecorder?
    /// Raw audio kept while calibrating (detector queue only).
    private var capture: [Float]?
    private var currentSampleRate: Double = 48000

    /// One device buffer copied by the realtime thread: how many samples went into the ring
    /// and when the buffer arrived (mach host time).
    private struct InputBlock {
        var frames: Int32
        var hostTime: UInt64
    }

    /// Owns the sample ring. Held by the worker's handler, so the ring outlives the worker
    /// thread (the queue joins it on release) and is freed after it.
    private final class SampleRing {
        let ring = SPSCRing<Float>.allocate(minimumCapacity: 1 << 18, blank: 0) // ~5 s at 48 kHz
        deinit { ring.deallocate() }
    }

    private let samples = SampleRing()
    private var blocks: RealtimeEventQueue<InputBlock>!

    /// Recent input level (0–1), updated on the main queue.
    public private(set) var level: Float = 0
    /// The level a note must reach to start (the noise gate in use), updated on the main queue.
    public private(set) var gateLevel: Float = 0
    /// Gate for the detector (detector queue only).
    private var pendingGate: Float?

    /// A noise gate from calibration or "Measure silence" (RMS level). nil: the detector
    /// measures the room itself for a moment after starting. Takes effect at once.
    public var noiseGate: Float? {
        didSet {
            let value = noiseGate
            queue.async { [weak self] in
                self?.pendingGate = value
                self?.detector?.fixedGate = value
                self?.recorder?.log("gate " + (value.map { String(format: "%.5f", $0) } ?? "auto"))
            }
        }
    }
    public private(set) var isRunning = false
    /// Name of the microphone being listened to.
    public private(set) var deviceName = ""
    #if os(macOS)
    /// The input to listen to, by `AudioDeviceInfo.uid`; nil (or one that's gone): the
    /// built-in microphone. Takes effect the next time listening starts.
    public var preferredInputUID: String?
    #endif

    public init(onNoteOn: @escaping NoteOn, onNoteOff: @escaping NoteOff) {
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
        let samples = self.samples
        blocks = RealtimeEventQueue(capacity: 1024, blank: InputBlock(frames: 0, hostTime: 0),
                                    name: "PianoPad.audio-input.drain") { [weak self] batch in
            // Worker thread: copy each block out of the ring and analyse it on the detector queue.
            var chunks: [([Float], Double)] = []
            chunks.reserveCapacity(batch.count)
            for block in batch {
                var chunk = [Float](repeating: 0, count: Int(block.frames))
                let read = chunk.withUnsafeMutableBufferPointer { samples.ring.pop(into: $0) }
                if read < chunk.count { chunk.removeLast(chunk.count - read) }
                chunks.append((chunk, AVAudioTime.seconds(forHostTime: block.hostTime)))
            }
            guard let self else { return }
            self.queue.async {
                for (chunk, arrival) in chunks where !chunk.isEmpty {
                    self.analyse(chunk, arrival: arrival, sampleRate: self.currentSampleRate)
                }
            }
        }
    }

    deinit {
        // Stop the realtime callback before the ring and queue are released.
        stop()
    }

    /// The chord the player should strike next, so the detector listens for it and its likely mistakes.
    public var expected: Set<Int> = [] {
        didSet {
            let value = expected
            queue.async { [weak self] in
                self?.pendingExpected = value
                self?.detector?.expected = value
                self?.recorder?.log("expect " + value.sorted().map(String.init).joined(separator: " "))
            }
        }
    }

    /// A calibrated piano (nil: the generic piano model). Takes effect at once.
    public var profile: PianoProfile? {
        didSet {
            let value = profile
            queue.async { [weak self] in
                guard let self, let old = self.detector else { return }
                var settings = PianoNoteDetector.Settings()
                settings.profile = value
                let detector = PianoNoteDetector(sampleRate: old.sampleRate, settings: settings)
                detector.expected = self.pendingExpected
                detector.fixedGate = self.pendingGate
                self.detector = detector
                self.strikeFilter.reset()
            }
        }
    }

    /// Starts keeping the raw audio (for calibration). Notes heard meanwhile aren't reported.
    public func startCapture() {
        queue.async { [weak self] in self?.capture = [] }
    }

    /// Stops keeping audio and hands over what was captured, with its sample rate (main queue).
    public func finishCapture(_ done: @escaping ([Float], Double) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let samples = self.capture ?? []
            self.capture = nil
            self.detector?.reset()
            self.strikeFilter.reset()
            let rate = self.currentSampleRate
            DispatchQueue.main.async { done(samples, rate) }
        }
    }

    /// Ignore what the microphone hears (e.g. while the reference plays through the speakers);
    /// unmuting forgets the sound so far.
    public func setMuted(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.muted && !value {
                self.detector?.reset()
                self.strikeFilter.reset()
            }
            self.muted = value
            self.recorder?.log(value ? "mute" : "unmute")
        }
    }

    /// Asks for microphone permission if needed, then starts listening.
    public func start(completion: @escaping (Error?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(startEngine())
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? self.startEngine() : AudioInputError.permissionDenied)
                }
            }
        default:
            completion(AudioInputError.permissionDenied)
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sink { engine.detach(sink) }
        let recorder = self.recorder
        self.recorder = nil
        queue.async { recorder?.close() }
        sink = nil
        isRunning = false
        level = 0
    }

    private func startEngine() -> Error? {
        guard !isRunning else { return nil }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            return AudioInputError.engine(error)
        }
        #endif
        let input = engine.inputNode

        #if os(macOS)
        // Listen to the chosen input, else the Mac's built-in microphone, not whatever the
        // system default input is (an iPhone, AirPods or a virtual device would hear the piano
        // badly or not at all).
        let chosen = preferredInputUID.flatMap { AudioDevices.device(uid: $0) }.map { AudioDeviceID($0.id) }
        if let unit = input.audioUnit, var device = chosen ?? MacAudioDevices.builtInInput() {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        if let unit = input.audioUnit {
            var current = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            if AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size) == noErr {
                deviceName = MacAudioDevices.name(of: current) ?? ""
            }
        }
        // Smaller device buffers: the default (often 512 frames or more) adds latency.
        if let unit = input.audioUnit {
            var frames: UInt32 = 256
            AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                                 &frames, UInt32(MemoryLayout<UInt32>.size))
        }
        #endif

        // Read the format after choosing the device: it's the device's.
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return AudioInputError.noInput }

        var settings = PianoNoteDetector.Settings()
        settings.profile = profile
        let detector = PianoNoteDetector(sampleRate: format.sampleRate, settings: settings)
        let rate = format.sampleRate
        queue.async { [weak self] in
            self?.currentSampleRate = rate
            detector.fixedGate = self?.pendingGate
        }
        detector.expected = pendingExpected
        self.detector = detector
        queue.async { [weak self] in self?.strikeFilter.reset() }
        let sampleRate = format.sampleRate
        let recorder = AppEnvironment.recordsMicForDebugging ? MicRecorder(sampleRate: sampleRate) : nil
        let device = deviceName
        queue.async { [weak self] in self?.recorder = recorder; recorder?.log("device \(device) \(Int(sampleRate)) Hz \(format.channelCount) ch"); recorder?.log("expect " + detector.expected.sorted().map(String.init).joined(separator: " ")) }

        // The sink is called on the realtime audio thread with each device buffer. It captures
        // only the ring and the poster (structs of raw pointers, no objects), copies channel 0
        // and posts the block; the worker thread does the rest.
        let ring = samples.ring
        let poster = blocks.poster
        let sink = AVAudioSinkNode { _, frameCount, bufferList in
            let arrival = mach_absolute_time()
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            guard buffers.count > 0, let data = buffers[0].mData, frameCount > 0 else { return noErr }
            // Only write samples if their block record will fit, so the two stay in step.
            guard poster.hasRoom else { return noErr }
            let channels = Int(max(1, buffers[0].mNumberChannels))
            let written = ring.push(from: data.assumingMemoryBound(to: Float.self), count: Int(frameCount), stride: channels)
            if written > 0 { poster.post(InputBlock(frames: Int32(written), hostTime: arrival)) }
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        self.sink = sink
        do {
            try engine.start()
        } catch {
            engine.detach(sink)
            self.sink = nil
            return AudioInputError.engine(error)
        }
        isRunning = true
        return nil
    }

    /// Runs on the detector queue.
    private func analyse(_ samples: [Float], arrival: Double, sampleRate: Double) {
        guard let detector else { return }
        recorder?.append(samples)
        let capturing = capture != nil
        if capturing { capture!.append(contentsOf: samples) }
        let heard = detector.process(samples)
        if let recorder, !capturing {
            for e in heard {
                recorder.log(e.kind == .on
                    ? "on \(e.pitch) " + String(format: "t=%.3f conf=%.2f str=%.1f", e.time, e.confidence, e.strength)
                    : "off \(e.pitch) " + String(format: "t=%.3f", e.time))
            }
        }
        let events = capturing ? [] : strikeFilter.filter(heard, expected: detector.expected) { [recorder] e, why in
            recorder?.log("drop \(e.pitch) " + (why == .spill ? "spill" : "weak"))
        }
        let level = detector.level
        let gate = detector.gateLevel
        let muted = self.muted
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.level = level
            self.gateLevel = gate
            guard !muted else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for e in events {
                // The detector's own clock counts samples; place the event relative to now.
                let time = now - (e.reportedAt - e.time) - max(0, now - arrival)
                switch e.kind {
                case .on: self.onNoteOn(e.pitch, time)
                case .off: self.onNoteOff(e.pitch, time)
                }
            }
        }
    }
}

/// Saves what the microphone hears to ~/Music/PianoPad Mic/<time>.wav, with a .log of the
/// expected chords and detected notes (positions in samples), for tuning the detector.
final class MicRecorder {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let logHandle: FileHandle?
    private var position: Int64 = 0

    init?(sampleRate: Double) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/PianoPad Mic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let file = try? AVAudioFile(forWriting: dir.appendingPathComponent(stamp + ".wav"), settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
              ], commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        self.format = format
        self.file = file
        let logURL = dir.appendingPathComponent(stamp + ".log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    func append(_ samples: [Float]) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try? file.write(from: buffer)
        position += Int64(samples.count)
    }

    func log(_ line: String) {
        logHandle?.write(Data("\(position) \(line)\n".utf8))
    }

    func close() {
        try? logHandle?.close()
    }
}
#if os(macOS)
/// Finding audio devices with Core Audio.
enum MacAudioDevices {
    /// The built-in microphone (the first built-in device with input streams).
    static func builtInInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids where isBuiltIn(id) && hasInput(id) { return id }
        return nil
    }

    static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func isBuiltIn(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}
#endif
#endif
