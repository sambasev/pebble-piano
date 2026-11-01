import Foundation

/// Provides standardized, deterministic audio benchmarks and ground-truth notes for evaluating
/// piano audio-to-MIDI transcription models across registers, dynamics, polyphony, and acoustic environments.
public enum AudioBenchmarkCorpus {
    public enum Environment: String, CaseIterable, Sendable {
        case dry = "dry"
        case room = "room"
        case noisy = "noisy"
    }

    public struct TestCase: Sendable {
        public var name: String
        public var description: String
        public var audio: [Float]
        public var sampleRate: Double
        public var truthNotes: [NoteEvent]
        public var guideChords: [ChordEvent]
        public var environment: Environment

        public init(
            name: String,
            description: String,
            audio: [Float],
            sampleRate: Double,
            truthNotes: [NoteEvent],
            guideChords: [ChordEvent],
            environment: Environment
        ) {
            self.name = name
            self.description = description
            self.audio = audio
            self.sampleRate = sampleRate
            self.truthNotes = truthNotes
            self.guideChords = guideChords
            self.environment = environment
        }
    }

    /// Physical struck-string audio synthesizer for deterministic, reproducible test generation.
    public static func render(
        notes: [(pitch: Int, start: Double, duration: Double, velocity: Int)],
        sampleRate: Double = 48000.0,
        leadInSilence: Double = 0.8,
        environment: Environment = .dry
    ) -> (audio: [Float], truth: [NoteEvent], guide: [ChordEvent]) {
        let maxEnd = (notes.map { $0.start + $0.duration }.max() ?? 1.0) + 1.0
        let totalSamples = Int((leadInSilence + maxEnd) * sampleRate)
        var audio = [Float](repeating: 0, count: totalSamples)

        // Seeded PRNG for reproducible room noise
        var seed: UInt64 = 123456789
        func randFloat() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }

        // Room noise baseline
        let baseNoise: Float = environment == .noisy ? 0.003 : (environment == .room ? 0.0006 : 0.0002)
        for i in audio.indices {
            audio[i] = randFloat() * baseNoise
        }

        var truthEvents: [NoteEvent] = []

        // Render string physics for each note
        for note in notes {
            let actualStart = leadInSilence + note.start
            let firstSample = Int(actualStart * sampleRate)
            let f0 = 440.0 * pow(2.0, Double(note.pitch - 69) / 12.0)
            let velScale = Float(note.velocity) / 100.0

            truthEvents.append(
                NoteEvent(
                    pitch: note.pitch,
                    onset: actualStart,
                    offset: actualStart + note.duration,
                    velocity: note.velocity,
                    channel: 0
                )
            )

            // String partials with inharmonicity (B = 0.0004)
            for h in 1...10 {
                let fh = Double(h) * f0 * (1.0 + 0.0004 * Double(h * h)).squareRoot()
                guard fh < min(8000.0, sampleRate * 0.45) else { break }

                let amp = Double(0.08 * velScale) / pow(Double(h), 0.9)
                let decayRate = 1.5 + 0.35 * Double(h)

                for i in firstSample..<audio.count {
                    let t = Double(i - firstSample) / sampleRate
                    if t > note.duration + 1.5 { break }
                    let sample = Float(amp * exp(-t * decayRate) * sin(2.0 * Double.pi * fh * t))
                    audio[i] += sample
                }
            }
        }

        // Apply room impulse response if room or noisy
        if environment == .room || environment == .noisy {
            let rt60 = environment == .noisy ? 0.6 : 0.35
            let irLen = min(Int(rt60 * sampleRate), 12000)
            var ir = [Float](repeating: 0, count: irLen)
            for j in 0..<irLen {
                let t = Double(j) / sampleRate
                ir[j] = randFloat() * Float(exp(-6.9 * t / rt60))
            }
            ir[0] = 1.0

            // Simple direct + reflection mix
            var reverbed = audio
            for i in 100..<audio.count {
                let step = min(i, 4000)
                var acc: Float = 0
                var k = 100
                while k < step {
                    acc += audio[i - k] * ir[k % irLen] * 0.0005
                    k += 40
                }
                reverbed[i] += acc
            }
            audio = reverbed
        }

        let guideChords = ChordGrouping.group(truthEvents, window: 0.05)
        return (audio, truthEvents, guideChords)
    }

    /// Generates the standard benchmark test suite.
    public static func standardSuite(environments: [Environment] = [.dry, .room, .noisy]) -> [TestCase] {
        var cases: [TestCase] = []

        for env in environments {
            // 1. C Major Scale (Monophonic, single notes across middle register)
            let scaleNotes = [60, 62, 64, 65, 67, 69, 71, 72].enumerated().map { (idx, p) in
                (pitch: p, start: Double(idx) * 0.6, duration: 0.5, velocity: 80)
            }
            let (scaleAudio, scaleTruth, scaleGuide) = render(notes: scaleNotes, environment: env)
            cases.append(
                TestCase(
                    name: "scale-c-major.\(env.rawValue)",
                    description: "Ascending C major scale C4–C5 at 80 velocity (\(env.rawValue))",
                    audio: scaleAudio,
                    sampleRate: 48000,
                    truthNotes: scaleTruth,
                    guideChords: scaleGuide,
                    environment: env
                )
            )

            // 2. Polyphonic Chords (Triads and 4-note chords)
            let chordNotes: [(pitch: Int, start: Double, duration: Double, velocity: Int)] = [
                // C major (C4, E4, G4)
                (60, 0.0, 0.8, 85), (64, 0.0, 0.8, 82), (67, 0.0, 0.8, 80),
                // F major (F4, A4, C5)
                (65, 1.2, 0.8, 85), (69, 1.2, 0.8, 83), (72, 1.2, 0.8, 81),
                // G7 (G3, F4, B4, D5)
                (55, 2.4, 0.8, 90), (65, 2.4, 0.8, 82), (71, 2.4, 0.8, 84), (74, 2.4, 0.8, 80),
                // C major resolution
                (60, 3.6, 1.0, 85), (64, 3.6, 1.0, 82), (67, 3.6, 1.0, 80)
            ]
            let (chordAudio, chordTruth, chordGuide) = render(notes: chordNotes, environment: env)
            cases.append(
                TestCase(
                    name: "polyphonic-chords.\(env.rawValue)",
                    description: "Polyphonic triads and 4-note chords C-F-G7-C (\(env.rawValue))",
                    audio: chordAudio,
                    sampleRate: 48000,
                    truthNotes: chordTruth,
                    guideChords: chordGuide,
                    environment: env
                )
            )

            // 3. Performance with Mistakes (Neighbor errors and extra keys)
            // Guide expects C4-D4-E4-F4-G4
            let targetNotes: [(pitch: Int, start: Double, duration: Double, velocity: Int)] = [
                (60, 0.0, 0.5, 80), (62, 0.7, 0.5, 80), (64, 1.4, 0.5, 80), (65, 2.1, 0.5, 80), (67, 2.8, 0.5, 80)
            ]
            // Played: C4, D#4 (wrong instead of D), E4, F#4 (wrong instead of F), G4
            let playedMistakes: [(pitch: Int, start: Double, duration: Double, velocity: Int)] = [
                (60, 0.0, 0.5, 80),
                (63, 0.7, 0.5, 80), // D# instead of D (neighbor mistake!)
                (64, 1.4, 0.5, 80),
                (66, 2.1, 0.5, 80), // F# instead of F (neighbor mistake!)
                (67, 2.8, 0.5, 80)
            ]
            let (mistakeAudio, mistakeTruth, _) = render(notes: playedMistakes, environment: env)
            let (_, _, intendedGuide) = render(notes: targetNotes, environment: env)

            cases.append(
                TestCase(
                    name: "mistakes-neighbor.\(env.rawValue)",
                    description: "Score wants C-D-E-F-G but player struck D# and F# mistakes (\(env.rawValue))",
                    audio: mistakeAudio,
                    sampleRate: 48000,
                    truthNotes: mistakeTruth,
                    guideChords: intendedGuide,
                    environment: env
                )
            )

            // 4. Bass & Treble Registers
            let wideRegisterNotes: [(pitch: Int, start: Double, duration: Double, velocity: Int)] = [
                (36, 0.0, 0.7, 85), // C2 (Bass)
                (48, 0.8, 0.7, 80), // C3
                (60, 1.6, 0.7, 80), // C4 (Mid)
                (72, 2.4, 0.7, 80), // C5
                (84, 3.2, 0.7, 80), // C6 (Treble)
                (96, 4.0, 0.7, 75)  // C7
            ]
            let (wideAudio, wideTruth, wideGuide) = render(notes: wideRegisterNotes, environment: env)
            cases.append(
                TestCase(
                    name: "wide-register.\(env.rawValue)",
                    description: "Octaves spanning C2 through C7 to test frequency extremes (\(env.rawValue))",
                    audio: wideAudio,
                    sampleRate: 48000,
                    truthNotes: wideTruth,
                    guideChords: wideGuide,
                    environment: env
                )
            )
        }

        return cases
    }
}
