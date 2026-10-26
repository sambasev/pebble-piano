#if os(macOS)
import Foundation
import PianoGraderCore
import PianoPadState

/// What a lesson needs from the player. `PlaySession` is the only conformer; the lesson
/// runner (M3b) drives it through this, so lesson logic stays out of `PlaySession`.
protocol PlayerControl: AnyObject {
    var lessonObserver: PlayerObserver? { get set }

    /// Enters lesson mode for `piece` (a page): saves the practice setup, stops the music and
    /// sends events to `observer`. `endLesson()` puts everything back.
    func beginLesson(piece: PieceID, observer: PlayerObserver)

    /// Unloads the music, for blocks with nothing to play against (explain, concept).
    func showNothing()

    /// Loads a lesson block's MIDI file, in wait mode or play-along. It isn't added to recent
    /// pieces, its takes are saved under `piece`, and play-along may run on clicks alone.
    /// `tempo` retimes the file (nil keeps its own). The first call saves the practice setup;
    /// `endLesson()` puts it back. `measures` (1-based) plays only those bars: the bar drill.
    func loadLessonBlock(midi: URL, piece: PieceID, mode: PlaySession.PracticeMode,
                         tempo: Double?, countInBeats: Int, measures: ClosedRange<Int>?)

    /// Bars in the loaded music.
    var lessonMeasureCount: Int { get }

    /// Bars replayed (or stopped on, waiting for a note) in the current take.
    var replaysThisTake: Int { get }

    /// Replays in the current take by measure (1-based), for choosing a bar to drill.
    var replaysByMeasure: [Int: Int] { get }

    /// Plays the loaded passage with its keys lit; `playerListenFinished()` when it ends.
    func startListening()
    func stopListening()

    /// Play-along from the first bar: count-in, then the playhead over clicks (or the
    /// block's backing track). The take is graded at the end.
    func startTimedRun()

    /// Throws the current take away and goes back to the start of the block.
    func restartBlock()

    /// Play-along speed for this block, as a percentage of the music's tempo.
    func setLessonTempo(percent: Double)

    /// How play-along judges this block (nil: the learner's own strictness).
    func setLessonPlayAlong(_ settings: Rubric.PlayAlong?)

    /// Leaves lesson mode and restores the practice piece, mode, tempo and metronome.
    func endLesson()
}

/// What the player reports back to a lesson. All calls arrive on the main thread.
protocol PlayerObserver: AnyObject {
    /// Any key went down (from any input), before it's judged.
    func playerNotePlayed(_ pitch: Int, source: InputSource)
    /// Wait mode: a key outside chord `chord` (index in the passage) while waiting on it.
    func playerWrongNote(onChord chord: Int)
    /// Wait mode: chord `chord` was played cleanly and the guide moved on.
    func playerChordPlayed(_ chord: Int)
    /// A listen run reached the end by itself (not when stopped).
    func playerListenFinished()
    /// Play-along: a key was judged against the music (`matched`: it belonged to a chord due then).
    func playerPlayAlongNote(matched: Bool)
    /// Play-along: too many misses, so a bar plays again (or the music stopped to wait for a note).
    func playerBarReplayed()
    /// A take was graded. `helpUsed`: slowed down, or stopped to wait for notes.
    func playerGraded(_ report: GradeReport, rubric: Rubric, helpUsed: Bool)
}

/// The Practice tab's setup, kept while a lesson borrows the session.
struct PracticeSnapshot {
    var mode: PlaySession.PracticeMode
    var tempoPercent: Double
    var metronomeOn: Bool
    var pieceTag: String
}

extension PlaySession: PlayerControl {
    var isInLesson: Bool { lessonPiece != nil }

    func beginLesson(piece: PieceID, observer: PlayerObserver) {
        savePracticeSetup()
        stopAudition()
        stopPlayAlong(discard: true)
        lessonPiece = piece
        lessonObserver = observer
    }

    func showNothing() {
        unloadReference()
    }

    private func savePracticeSetup() {
        guard practiceBeforeLesson == nil else { return }
        practiceBeforeLesson = PracticeSnapshot(mode: mode, tempoPercent: tempoPercent,
                                                metronomeOn: metronomeOn, pieceTag: currentPieceTag)
    }

    func loadLessonBlock(midi: URL, piece: PieceID, mode newMode: PracticeMode,
                         tempo: Double?, countInBeats: Int, measures: ClosedRange<Int>? = nil) {
        savePracticeSetup()
        stopAudition()
        stopPlayAlong(discard: true)
        lessonPiece = piece
        lessonCountInBeats = max(1, countInBeats)
        lessonPlayAlong = nil
        tempoPercent = 100
        setModeNow(newMode)
        loadReference(midi, tempo: tempo, remember: false, measures: measures)
    }

    var lessonMeasureCount: Int { reference?.measureCount ?? 0 }

    var replaysThisTake: Int { rewindsPerBar.values.reduce(0, +) }

    var replaysByMeasure: [Int: Int] {
        Dictionary(uniqueKeysWithValues: rewindsPerBar.map { ($0.key + 1, $0.value) })
    }

    func startListening() {
        startAudition()
    }

    func stopListening() {
        stopAudition()
    }

    func startTimedRun() {
        if mode != .playAlong { setModeNow(.playAlong) }
        startPlayAlong(fromBar: 0)
    }

    func restartBlock() {
        resetAll()
    }

    func setLessonTempo(percent: Double) {
        tempoPercent = min(Self.tempoRange.upperBound, max(Self.tempoRange.lowerBound, percent))
    }

    func setLessonPlayAlong(_ settings: Rubric.PlayAlong?) {
        lessonPlayAlong = settings
        configureJudge()
    }

    func endLesson() {
        stopAudition()
        stopPlayAlong(discard: true)
        lessonObserver = nil
        lessonPiece = nil
        lessonCountInBeats = 4
        lessonPlayAlong = nil
        guard let saved = practiceBeforeLesson else { return }
        practiceBeforeLesson = nil
        setModeNow(saved.mode)
        tempoPercent = saved.tempoPercent
        metronomeOn = saved.metronomeOn
        if !saved.pieceTag.isEmpty { selectPiece(saved.pieceTag) }
    }

    /// Changes `mode` and applies it now, rather than on the next turn of the run loop as the
    /// picker does. A lesson loads, changes mode and starts listening in one go; a deferred
    /// mode change would stop that listen.
    func setModeNow(_ newMode: PracticeMode) {
        guard mode != newMode else { return }
        settingModeDirectly = true
        mode = newMode
        settingModeDirectly = false
        modeChanged()
    }

    /// Called after every graded take (wait mode and play-along).
    func reportGradeToLesson() {
        guard let lessonObserver, let report else { return }
        let slowed = tempoPercent < 99.5
        let waited = missMode == .waitForNote && !rewindsPerBar.isEmpty
        lessonObserver.playerGraded(report, rubric: rubric, helpUsed: slowed || waited)
    }
}

#endif
