import XCTest
@testable import PianoGraderCore

final class BackingTrackTests: XCTestCase {
    func track() -> BackingTrack {
        BackingTrack(name: "Song", audioPath: "/tmp/song.m4a", duration: 30, trimStart: 1, trimEnd: 20,
                     bar1Seconds: 2.5, bpm: 120, timeSignature: TimeSignature(numerator: 3, denominator: 4),
                     key: "G", countInBars: 2)
    }

    func testBarTimesAndLines() {
        let t = track()                                   // 3/4 at 120: 1.5 s per bar
        XCTAssertEqual(t.barSeconds, 1.5, accuracy: 1e-9)
        XCTAssertEqual(t.beatSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.barStartSeconds(1), 2.5, accuracy: 1e-9)
        XCTAssertEqual(t.barStartSeconds(3), 5.5, accuracy: 1e-9)
        let lines = t.barLines()
        XCTAssertEqual(lines.first?.bar, 0)                 // 1.0 s: the bar before bar 1
        XCTAssertEqual(lines.first?.seconds ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(lines.last?.bar, 12)                 // 2.5 + 11 × 1.5 = 19.0 (bar 13 would be 20.5)
        XCTAssertEqual(lines.last?.seconds ?? 0, 19, accuracy: 1e-9)
        XCTAssertEqual(t.barCount, 11)                      // (20 − 2.5) / 1.5 = 11.67
    }

    func testClampKeepsMarkersInOrder() {
        var t = track()
        t.bar1Seconds = 0.2                                 // before the trim start
        t.trimEnd = 40                                      // past the end of the file
        t.bpm = 0
        t.clamp()
        XCTAssertEqual(t.bar1Seconds, 1)
        XCTAssertNil(t.trimEnd)
        XCTAssertEqual(t.playEnd, 30)
        XCTAssertEqual(t.bpm, 20)
    }

    func testAnnotationCarriesBar1AndTrim() {
        let a = track().annotation(audioPath: "/x.m4a")
        XCTAssertEqual(a.file, "/x.m4a")
        XCTAssertEqual(a.startSeconds, 2.5)
        XCTAssertEqual(a.trimStartSeconds, 1)
        XCTAssertEqual(a.trimEndSeconds, 20)
        XCTAssertEqual(a.countInBars, 2)
        XCTAssertEqual(a.timeSignature.numerator, 3)
    }

    func testLibrarySavesLinksAndDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = BackingTrackLibrary(directory: dir)
        XCTAssertTrue(library.tracks().isEmpty)
        let t = track()
        try library.save(t)
        XCTAssertEqual(library.tracks().map(\.id), [t.id])
        XCTAssertEqual(library.track(t.id)?.timeSignature, TimeSignature(numerator: 3, denominator: 4))
        XCTAssertEqual(library.track(t.id)?.trimEnd, 20)

        let key = BackingLinkKey.passage(book: "book.pdf", id: "p29")
        try library.link(key, to: t.id)
        XCTAssertEqual(library.linkedTrackID(for: key), t.id)
        try library.link(key, to: nil)
        XCTAssertNil(library.linkedTrackID(for: key))

        try library.link(key, to: t.id)
        try library.delete(t.id)
        XCTAssertNil(library.track(t.id))
        XCTAssertNil(library.linkedTrackID(for: key))     // links to a deleted track go too
    }

    func testResolveAudioFindsAMovedFileByName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = BackingTrackLibrary(directory: dir)
        var t = track()
        t.audioPath = "/nowhere/song.m4a"
        XCTAssertNil(library.resolveAudio(for: t))
        FileManager.default.createFile(atPath: dir.appendingPathComponent("song.m4a").path, contents: Data([0]))
        XCTAssertEqual(library.resolveAudio(for: t)?.lastPathComponent, "song.m4a")
    }
}

final class WaveformTests: XCTestCase {
    func testBuilderSummarisesBuckets() {
        var builder = WaveformBuilder(sampleRate: 1000, bucketsPerSecond: 100)   // 10 samples per bucket
        builder.append((0..<25).map { Float($0 % 2 == 0 ? $0 : -$0) / 100 })
        let peaks = builder.finish()
        XCTAssertEqual(peaks.bucketCount, 3)                                    // 10 + 10 + 5
        XCTAssertEqual(peaks.maxs[0], 0.08, accuracy: 1e-6)
        XCTAssertEqual(peaks.mins[0], -0.09, accuracy: 1e-6)
        XCTAssertEqual(peaks.duration, 0.03, accuracy: 1e-9)
        XCTAssertEqual(peaks.peak, 0.24, accuracy: 1e-6)
    }

    func testColumnsMergeAndPadOutsideTheAudio() {
        var builder = WaveformBuilder(sampleRate: 100, bucketsPerSecond: 100)     // 1 sample per bucket
        builder.append([0.1, -0.5, 0.3, 0.9])
        let peaks = builder.finish()
        let cols = peaks.columns(from: 0, to: 0.08, count: 4)                    // 2 buckets per column
        XCTAssertEqual(cols.count, 4)
        XCTAssertEqual(cols[0].min, -0.5, accuracy: 1e-6)
        XCTAssertEqual(cols[1].max, 0.9, accuracy: 1e-6)
        XCTAssertEqual(cols[3].max, 0)                                          // past the end
    }

    func testTapTempo() {
        var tap = TapTempo()
        XCTAssertNil(tap.tap(at: 10))
        tap.tap(at: 10.5)
        tap.tap(at: 11.0)
        XCTAssertEqual(tap.tap(at: 11.5) ?? 0, 120, accuracy: 1e-6)
        XCTAssertNil(tap.tap(at: 20))                                           // long pause: starts over
    }
}

final class RetimeTests: XCTestCase {
    func testRetimingKeepsBeatsAndChangesSeconds() {
        let seq = MIDISequence(notes: [
            NoteEvent(pitch: 60, onset: 0, offset: 0.5, onsetBeats: 0, offsetBeats: 1),
            NoteEvent(pitch: 62, onset: 0.5, offset: 0.75, onsetBeats: 1),            // no offsetBeats
        ], initialTempoBPM: 120)
        let slow = seq.retimed(bpm: 60)
        XCTAssertEqual(slow.initialTempoBPM, 60)
        XCTAssertEqual(slow.notes[0].offset, 1, accuracy: 1e-9)
        XCTAssertEqual(slow.notes[1].onset, 1, accuracy: 1e-9)
        XCTAssertEqual(slow.notes[1].onsetBeats, 1)
        XCTAssertEqual(slow.notes[1].offsetBeats ?? 0, 1.5, accuracy: 1e-9)      // 0.25 s at 120 = half a beat
        XCTAssertEqual(slow.notes[1].offset, 1.5, accuracy: 1e-9)
    }
}
