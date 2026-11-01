import Foundation

/// Common protocol implemented by all audio-to-MIDI piano transcription models and methods.
public protocol AudioTranscriber: AnyObject {
    /// Human-readable identifier for the model or method.
    var name: String { get }

    /// A brief description of the model configuration or algorithm.
    var methodDescription: String { get }

    /// The chord or pitches expected by the musical score (empty for free play / unconstrained).
    var expected: Set<Int> { get set }

    /// Feeds a chunk of mono audio samples at the configured sample rate and returns detected note events.
    func process(_ samples: [Float]) -> [DetectedNote]

    /// Resets all internal buffers, filter states, and activations between takes.
    func reset()
}

/// Standard Score-Informed NMF Transcriber (the production method used in PerfectPiano).
/// Uses dynamic score expectation penalties to favor the next expected chord while flagging mistakes.
public final class ScoreInformedTranscriber: AudioTranscriber {
    public let name = "Score-Informed NMF"
    public let methodDescription = "Real-time CQT + NMF with dynamic score expectation penalties"

    private let sampleRate: Double
    private let settings: PianoNoteDetector.Settings
    private var detector: PianoNoteDetector

    public var expected: Set<Int> = [] {
        didSet { detector.expected = expected }
    }

    public init(sampleRate: Double, settings: PianoNoteDetector.Settings = .init()) {
        self.sampleRate = sampleRate
        self.settings = settings
        self.detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
    }

    public func process(_ samples: [Float]) -> [DetectedNote] {
        detector.process(samples)
    }

    public func reset() {
        detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        detector.expected = expected
    }
}

/// Free-Play NMF Transcriber (uninformed baseline).
/// Runs the identical NMF engine but completely ignores score guidance (`expected` always forced to empty).
public final class FreePlayTranscriber: AudioTranscriber {
    public let name = "Free-Play NMF"
    public let methodDescription = "Unconstrained polyphonic NMF without score expectations (expected = [])"

    private let sampleRate: Double
    private let settings: PianoNoteDetector.Settings
    private var detector: PianoNoteDetector

    /// Ignored in free-play mode: the model operates without prior musical expectations.
    public var expected: Set<Int> {
        get { detector.expected }
        set { detector.expected = [] }
    }

    public init(sampleRate: Double, settings: PianoNoteDetector.Settings = .init()) {
        self.sampleRate = sampleRate
        self.settings = settings
        self.detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        self.detector.expected = []
    }

    public func process(_ samples: [Float]) -> [DetectedNote] {
        detector.process(samples)
    }

    public func reset() {
        detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        detector.expected = []
    }
}

/// Calibrated Piano Profile NMF Transcriber.
/// Uses measured tuning cents, string inharmonicity, and partial distributions from a calibration take.
public final class CalibratedTranscriber: AudioTranscriber {
    public let name = "Calibrated NMF"
    public let methodDescription = "Score-informed NMF using custom piano calibration profile"

    private let sampleRate: Double
    private var settings: PianoNoteDetector.Settings
    private var detector: PianoNoteDetector

    public var expected: Set<Int> = [] {
        didSet { detector.expected = expected }
    }

    public init(sampleRate: Double, profile: PianoProfile, settings: PianoNoteDetector.Settings = .init()) {
        self.sampleRate = sampleRate
        var s = settings
        s.profile = profile
        self.settings = s
        self.detector = PianoNoteDetector(sampleRate: sampleRate, settings: s)
    }

    public func process(_ samples: [Float]) -> [DetectedNote] {
        detector.process(samples)
    }

    public func reset() {
        detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        detector.expected = expected
    }
}

/// Configurable NMF Transcriber for latency/sensitivity parameter ablations.
public final class AblationTranscriber: AudioTranscriber {
    public let name: String
    public let methodDescription: String

    private let sampleRate: Double
    private let settings: PianoNoteDetector.Settings
    private var detector: PianoNoteDetector

    public var expected: Set<Int> = [] {
        didSet { detector.expected = expected }
    }

    public init(name: String, description: String, sampleRate: Double, settings: PianoNoteDetector.Settings) {
        self.name = name
        self.methodDescription = description
        self.sampleRate = sampleRate
        self.settings = settings
        self.detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
    }

    public func process(_ samples: [Float]) -> [DetectedNote] {
        detector.process(samples)
    }

    public func reset() {
        detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        detector.expected = expected
    }
}
