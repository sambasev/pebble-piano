import XCTest
@testable import PianoGraderCore

final class EvaluationSuiteTests: XCTestCase {
    private let rate = 48000.0

    func testSyntheticCorpusGeneration() {
        let (audio, truth, guide) = AudioBenchmarkCorpus.render(
            notes: [(pitch: 60, start: 0.0, duration: 0.5, velocity: 80)],
            sampleRate: rate,
            leadInSilence: 0.5,
            environment: .dry
        )

        XCTAssertFalse(audio.isEmpty)
        XCTAssertEqual(truth.count, 1)
        XCTAssertEqual(truth[0].pitch, 60)
        XCTAssertEqual(truth[0].onset, 0.5, accuracy: 1e-3)
        XCTAssertEqual(guide.count, 1)
        XCTAssertEqual(guide[0].pitches, [60])
    }

    func testAutoAlignmentOffsetEstimation() {
        // Render note starting at lead-in silence = 1.5s
        let (audio, _, _) = AudioBenchmarkCorpus.render(
            notes: [(pitch: 60, start: 0.0, duration: 0.5, velocity: 90)],
            sampleRate: rate,
            leadInSilence: 1.5,
            environment: .dry
        )

        // Artificially create a truth note with onset = 0.5s (meaning audio is 1.0s delayed relative to truth)
        let shiftedTruth = [NoteEvent(pitch: 60, onset: 0.5, offset: 1.0, velocity: 90)]

        let estimatedOffset = DetectorEvaluation.estimateOffset(audio: audio, sampleRate: rate, truth: shiftedTruth)
        // audio onset ≈ 1.5s, truth onset = 0.5s => offset ≈ +1.0s
        XCTAssertEqual(estimatedOffset, 1.0, accuracy: 0.15)
    }

    func testScoreInformedVsFreePlayTranscribers() {
        let scoreTranscriber = ScoreInformedTranscriber(sampleRate: rate)
        scoreTranscriber.expected = [60, 64]
        XCTAssertEqual(scoreTranscriber.expected, [60, 64])

        let freeTranscriber = FreePlayTranscriber(sampleRate: rate)
        freeTranscriber.expected = [60, 64]
        // Free-play transcriber should keep expected empty internally
        XCTAssertTrue(freeTranscriber.expected.isEmpty)
    }

    func testSpectralPeakTranscriberProcessesAudio() {
        let peakTranscriber = SpectralPeakTranscriber(sampleRate: rate)
        let (audio, _, _) = AudioBenchmarkCorpus.render(
            notes: [(pitch: 60, start: 0.0, duration: 0.4, velocity: 85)],
            sampleRate: rate,
            leadInSilence: 0.5,
            environment: .dry
        )

        let detected = peakTranscriber.process(audio)
        XCTAssertFalse(detected.isEmpty)
        let onEvents = detected.filter { $0.kind == .on }
        XCTAssertGreaterThan(onEvents.count, 0)
    }

    func testEvaluationResultMetrics() {
        let (audio, truth, guide) = AudioBenchmarkCorpus.render(
            notes: [
                (pitch: 60, start: 0.0, duration: 0.5, velocity: 85),
                (pitch: 64, start: 0.8, duration: 0.5, velocity: 85)
            ],
            sampleRate: rate,
            leadInSilence: 0.8,
            environment: .dry
        )

        let transcriber = ScoreInformedTranscriber(sampleRate: rate)
        let result = DetectorEvaluation.evaluate(
            transcriber: transcriber,
            audio: audio,
            sampleRate: rate,
            truth: truth,
            guide: guide,
            tolerance: 0.15,
            autoAlign: false
        )

        XCTAssertEqual(result.truthCount, 2)
        XCTAssertGreaterThanOrEqual(result.matched, 1)
        XCTAssertGreaterThan(result.precision, 0.5)
        XCTAssertGreaterThan(result.recall, 0.5)
        XCTAssertGreaterThan(result.f1, 0.5)
        XCTAssertGreaterThan(result.latency(percentile: 0.5), 0)
    }
}
