import XCTest
import PianoGraderCore
@testable import PianoLessons

final class NoteNameTests: XCTestCase {
    func testParsesNamesToMIDIPitches() {
        XCTAssertEqual(NoteName("C4")?.pitch, 60)
        XCTAssertEqual(NoteName("D4")?.pitch, 62)
        XCTAssertEqual(NoteName("e4")?.pitch, 64)
        XCTAssertEqual(NoteName("F#3")?.pitch, 54)
        XCTAssertEqual(NoteName("Bb4")?.pitch, 70)
        XCTAssertEqual(NoteName("B♭4")?.pitch, 70)
        XCTAssertEqual(NoteName("Cb4")?.pitch, 59)
        XCTAssertEqual(NoteName("A0")?.pitch, 21)
        XCTAssertEqual(NoteName("C-1")?.pitch, 0)
    }

    func testRejectsNonsense() {
        XCTAssertNil(NoteName(""))
        XCTAssertNil(NoteName("H4"))
        XCTAssertNil(NoteName("C"))
        XCTAssertNil(NoteName("C#"))
        XCTAssertNil(NoteName("C4x"))
        XCTAssertEqual(NoteName("G9")?.pitch, 127, "the top MIDI note")
        XCTAssertNil(NoteName("G#9"), "above MIDI's range")
    }

    func testNameRoundTrip() {
        XCTAssertEqual(NoteName(pitch: 61).name, "C#4")
        XCTAssertEqual(NoteName(pitch: 60).name, "C4")
        XCTAssertEqual(NoteName(pitch: 0).name, "C-1")
    }
}

final class LessonModelTests: XCTestCase {
    static let unitJSON = """
    {
      "id": "u1", "title": "Middle C position",
      "pages": [
        { "id": "p1", "title": "Meet Middle C", "newNotes": ["C4"], "unlocks": "p2",
          "blocks": [
            { "type": "explain", "text": "Find the 2 black keys", "highlight": ["C#4", "D#4"] },
            { "type": "explain", "text": "This is Middle C", "highlight": ["C4"], "advanceOn": "C4" },
            { "type": "wait", "midi": "p1-ex1.mid", "prompt": "Play the note C", "fingering": [1, 1, 1], "hand": "R" },
            { "type": "listen", "midi": "p1-ex2.mid", "tempo": 60 },
            { "type": "timed", "midi": "p1-ex2.mid", "tempo": 60 }
          ] },
        { "id": "p2", "title": "Finger numbers", "unlocks": "p3",
          "blocks": [ { "type": "concept", "card": "fingerNumbers", "text": "1 is your thumb", "check": "E4" } ] },
        { "id": "p3", "title": "Goal song",
          "blocks": [ { "type": "songChallenge", "midi": "mary.mid", "title": "Mary Had a Little Lamb" } ] }
      ]
    }
    """

    func decode() throws -> LessonUnit {
        try JSONDecoder().decode(LessonUnit.self, from: Data(Self.unitJSON.utf8))
    }

    func testPreviewBlockPrefersSongThenListening() throws {
        let unit = try decode()
        XCTAssertEqual(unit.pages[0].previewBlock?.kind, .listen, "the listening exercise over wait and timed")
        XCTAssertNil(unit.pages[1].previewBlock, "a concept page has nothing to play")
        XCTAssertEqual(unit.pages[2].previewBlock?.midi, "mary.mid")
    }

    func testDecodesEveryBlockKind() throws {
        let unit = try decode()
        XCTAssertEqual(unit.pages.map(\.id), ["p1", "p2", "p3"])
        let p1 = unit.pages[0]
        XCTAssertEqual(p1.newNotes, [NoteName(pitch: 60)])
        XCTAssertEqual(p1.blocks.map(\.kind), [.explain, .explain, .wait, .listen, .timed])

        guard case .explain(let find) = p1.blocks[0], case .explain(let read) = p1.blocks[1] else {
            return XCTFail("expected explain blocks")
        }
        XCTAssertEqual(find.highlight.map(\.pitch), [61, 63])
        XCTAssertNil(find.advanceOn)
        XCTAssertEqual(read.advanceOn?.pitch, 60)

        guard case .wait(let ex) = p1.blocks[2] else { return XCTFail("expected wait") }
        XCTAssertEqual(ex.fingering, [1, 1, 1])
        XCTAssertEqual(ex.hand, .right)
        XCTAssertEqual(ex.prompt, "Play the note C")

        guard case .timed(let timed) = p1.blocks[4] else { return XCTFail("expected timed") }
        XCTAssertEqual(timed.countInBeats, 4, "count-in defaults to 4")
        XCTAssertEqual(timed.rubric, "beginner", "rubric defaults to beginner")

        guard case .concept(let card) = unit.pages[1].blocks[0] else { return XCTFail("expected concept") }
        XCTAssertEqual(card.check?.pitch, 64)

        guard case .songChallenge(let song) = unit.pages[2].blocks[0] else { return XCTFail("expected song") }
        XCTAssertEqual(song.practiceTempos, [0.7])
        XCTAssertNil(song.backing)
    }

    func testEncodeRoundTrip() throws {
        let unit = try decode()
        let data = try JSONEncoder().encode(unit)
        XCTAssertEqual(try JSONDecoder().decode(LessonUnit.self, from: data), unit)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""type":"songChallenge""#))
        XCTAssertTrue(text.contains(#""advanceOn":"C4""#))
    }

    func testUnknownBlockTypeFails() {
        let json = #"{"id":"u","title":"t","pages":[{"id":"p","title":"t","blocks":[{"type":"dance"}]}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LessonUnit.self, from: Data(json.utf8)))
    }

    func testBadNoteNameFails() {
        let json = #"{"id":"u","title":"t","pages":[{"id":"p","title":"t","blocks":[{"type":"explain","text":"x","advanceOn":"Q4"}]}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LessonUnit.self, from: Data(json.utf8)))
    }

    func testStarredBlocks() throws {
        let unit = try decode()
        XCTAssertEqual(unit.pages[0].starredBlocks, [4])
        XCTAssertEqual(unit.pages[1].starredBlocks, [])
        XCTAssertEqual(unit.pages[2].starredBlocks, [0])
    }

    func testUnlocking() throws {
        let unit = try decode()
        XCTAssertTrue(unit.isUnlocked("p1", completed: []))
        XCTAssertFalse(unit.isUnlocked("p2", completed: []))
        XCTAssertTrue(unit.isUnlocked("p2", completed: ["p1"]))
        XCTAssertFalse(unit.isUnlocked("p3", completed: ["p1"]))
        XCTAssertEqual(unit.nextPage(completed: [])?.id, "p1")
        XCTAssertEqual(unit.nextPage(completed: ["p1"])?.id, "p2")
        XCTAssertEqual(unit.nextPage(completed: ["p1", "p2"])?.id, "p3")
        XCTAssertNil(unit.nextPage(completed: ["p1", "p2", "p3"]))
    }
}

final class UnitLoaderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnitLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ json: String, midi: [String]) throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent(LoadedUnit.fileName))
        for name in midi {
            try Data("MThd".utf8).write(to: folder.appendingPathComponent(name))
        }
    }

    func testLoadsAValidUnit() throws {
        try write(LessonModelTests.unitJSON, midi: ["p1-ex1.mid", "p1-ex2.mid", "mary.mid"])
        let loaded = try LoadedUnit.load(folder: folder)
        XCTAssertEqual(loaded.unit.id, "u1")
        XCTAssertEqual(loaded.midiURL(for: loaded.unit.pages[0].blocks[2])?.lastPathComponent, "p1-ex1.mid")
        XCTAssertNil(loaded.midiURL(for: loaded.unit.pages[0].blocks[0]))
    }

    func testReportsMissingMIDI() throws {
        try write(LessonModelTests.unitJSON, midi: ["p1-ex1.mid"])
        XCTAssertThrowsError(try LoadedUnit.load(folder: folder)) { error in
            let errors = (error as? UnitLoadFailure)?.errors ?? []
            XCTAssertEqual(errors, [
                .missingMIDI(page: "p1", block: 3, path: "p1-ex2.mid"),
                .missingMIDI(page: "p1", block: 4, path: "p1-ex2.mid"),
                .missingMIDI(page: "p3", block: 0, path: "mary.mid"),
            ])
        }
    }

    func testReportsEveryStructuralProblem() {
        let unit = LessonUnit(id: "u", title: "t", pages: [
            LessonPage(id: "a", title: "A", blocks: [
                .wait(.init(midi: "x.mid", fingering: [1, 6])),
                .timed(.init(midi: "x.mid", tempo: 0)),
            ], unlocks: "zz"),
            LessonPage(id: "a", title: "A again", blocks: []),
        ])
        let errors = LoadedUnit(unit: unit, folder: folder).validate(fileExists: { _ in true })
        XCTAssertEqual(Set(errors.map(\.description)), Set([
            UnitError.duplicatePage("a"),
            .emptyPage("a"),
            .unknownUnlock(page: "a", target: "zz"),
            .badFingering(page: "a", block: 0, finger: 6),
            .badTempo(page: "a", block: 1),
        ].map(\.description)))
    }

    func testUnreadableFile() {
        XCTAssertThrowsError(try LoadedUnit.load(folder: folder)) { error in
            guard case .unreadable? = (error as? UnitLoadFailure)?.errors.first else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }
    }

    func testNoPages() {
        let errors = LoadedUnit(unit: LessonUnit(id: "u", title: "t", pages: []), folder: folder).validate()
        XCTAssertEqual(errors, [.noPages])
    }
}

/// The units shipped in Lessons/ load and pass validation.
final class BundledUnitTests: XCTestCase {
    func testUnit1Loads() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let loaded = try LoadedUnit.load(folder: root.appendingPathComponent("Lessons/unit1"))
        XCTAssertEqual(loaded.unit.id, "u1")
        let p1 = try XCTUnwrap(loaded.unit.page("p1"))
        XCTAssertEqual(p1.newNotes.map(\.name), ["C4"])
        XCTAssertEqual(p1.blocks.map(\.kind), [.explain, .explain, .wait, .wait, .listen, .timed])
        XCTAssertEqual(p1.starredBlocks, [5])

        // Pages open in order: 1 → 2 → … → 7, the goal song last.
        let ids = ["p1", "p2", "p3", "p4", "c1", "p5", "p6", "p7"]
        XCTAssertEqual(loaded.unit.pages.map(\.id), ids)
        XCTAssertEqual(loaded.unit.nextPage(completed: [])?.id, "p1")
        XCTAssertEqual(loaded.unit.nextPage(completed: ["p1", "p2"])?.id, "p3")
        XCTAssertEqual(loaded.unit.nextPage(completed: Set(ids.dropLast()))?.id, "p7")
        XCTAssertNil(loaded.unit.nextPage(completed: Set(ids)))
        XCTAssertEqual(loaded.unit.pages.filter(\.isGoalSongPage).map(\.id), ["p7"])
        XCTAssertEqual(loaded.unit.pages.filter(\.isCheckpointSong).map(\.id), ["c1"])
        XCTAssertEqual(loaded.unit.nextPage(completed: ["p1", "p2", "p3", "p4"])?.id, "c1", "the checkpoint follows E")
        XCTAssertEqual(loaded.unit.page("p5")?.newNotes.map(\.name), ["F4"])
        XCTAssertEqual(loaded.unit.page("p6")?.newNotes.map(\.name), ["G4"])
        XCTAssertEqual(loaded.unit.page("p4")?.newNotes.map(\.name), ["E4"])
        guard case .concept(let check)? = loaded.unit.page("p3")?.blocks.last else { return XCTFail("p3 ends with a check") }
        XCTAssertEqual(check.check?.name, "E4")
    }

    func testHintsFallBackToThePage() {
        let page = LessonPage(id: "p", title: "t", blocks: [
            .wait(.init(midi: "a.mid")),
            .wait(.init(midi: "b.mid", hint: "Own hint")),
        ], hint: "Page hint")
        XCTAssertEqual(page.hint(forBlock: 0), "Page hint")
        XCTAssertEqual(page.hint(forBlock: 1), "Own hint")
        XCTAssertEqual(page.hint(forBlock: 9), "Page hint")
        XCTAssertNil(LessonPage(id: "q", title: "t", blocks: [.wait(.init(midi: "a.mid"))]).hint(forBlock: 0))
    }
}

final class GoalSongsTests: XCTestCase {
    /// Every goal song has its MIDI in Lessons/unit1/songs/, in Middle C position (C4–G4).
    func testEverySongHasItsMIDI() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let unit = root.appendingPathComponent("Lessons/unit1")
        for song in GoalSongs.all {
            let url = unit.appendingPathComponent(Block.SongChallenge.goalSongPath(song.id))
            let sequence = try MIDIFile.read(url: url)
            XCTAssertFalse(sequence.notes.isEmpty, song.id)
            let pitches = Set(sequence.notes.map(\.pitch))
            XCTAssertTrue(pitches.isSubset(of: [60, 62, 64, 65, 67]), "\(song.id): \(pitches.sorted())")
            XCTAssertEqual(pitches, Set(song.notes.map(\.pitch)), "\(song.id) uses the notes its card lists")
        }
    }

    func testGoalSongFlagDecodes() throws {
        let json = #"{"type":"songChallenge","midi":"songs/mary.mid","title":"Your song","useGoalSong":true}"#
        guard case .songChallenge(let b) = try JSONDecoder().decode(Block.self, from: Data(json.utf8)) else {
            return XCTFail("expected a song challenge")
        }
        XCTAssertTrue(b.useGoalSong)
        let plain = #"{"type":"songChallenge","midi":"x.mid","title":"x"}"#
        guard case .songChallenge(let p) = try JSONDecoder().decode(Block.self, from: Data(plain.utf8)) else {
            return XCTFail("expected a song challenge")
        }
        XCTAssertFalse(p.useGoalSong, "defaults to off")
        XCTAssertEqual(Block.SongChallenge.goalSongPath("odeToJoy"), "songs/odeToJoy.mid")
    }

    func testCatalogue() {
        XCTAssertEqual(GoalSongs.all.count, 4)
        XCTAssertEqual(Set(GoalSongs.all.map(\.id)).count, 4, "unique IDs")
        XCTAssertEqual(GoalSongs.song(GoalSongs.defaultID)?.title, "Mary Had a Little Lamb")
        XCTAssertNil(GoalSongs.song("nope"))
        XCTAssertNil(GoalSongs.song(nil))
        // Every song fits Middle C position: C4 to G4, right hand.
        for song in GoalSongs.all {
            XCTAssertFalse(song.notes.isEmpty, song.id)
            XCTAssertTrue(song.notes.allSatisfy { (60...67).contains($0.pitch) }, song.id)
        }
    }
}
