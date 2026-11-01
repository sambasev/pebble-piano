#if os(macOS)
import AppKit
import CoreAudioKit
import Foundation
import PDFKit
import PianoGraderCore
import PianoGraderIO
import PianoAI
import PianoLessons
import PianoPadState
import EarTrainingUI
import EarTrainingIntegration
import UniformTypeIdentifiers

/// A book's PDF and its annotations, loaded together.
struct LoadedBook {
    let annotations: BookAnnotations
    /// Folder holding the annotations file; passage paths are relative to it.
    let baseURL: URL
    let document: PDFDocument
}

/// Everything one PianoPad window does: the book page, input from the computer keyboard
/// and MIDI, recording a take, the live green/red guide and playhead, and grading.
/// All methods run on the main thread (AppKit events and MIDIInput both deliver there).
final class PlaySession: ObservableObject {
    enum Phase: Equatable {
        case waiting    // armed; the first note starts the take
        case recording
        case graded
    }

    enum RubricChoice: String, CaseIterable, Identifiable {
        case beginner, intermediate, file
        var id: String { rawValue }
    }

    /// Wait: the playhead holds on each chord until it's played. Play-along: the backing
    /// track (or a click) keeps time, and a bar with too many misses is played again.
    enum PracticeMode: String, CaseIterable, Identifiable {
        case wait, playAlong
        var id: String { rawValue }
    }

    enum PlayAlongState: Equatable {
        case idle
        case countIn
        case playing
        /// Too many misses in this bar (0-based): pausing before playing it again.
        case rewinding(bar: Int)
        /// Wait-for-note mode: the music has stopped on a chord until it is played.
        case waitingForNote(chord: Int, bar: Int)
        case finished
    }

    // MARK: Published state

    @Published private(set) var phase: Phase = .waiting
    @Published private(set) var referenceURL: URL?
    @Published private(set) var reference: MIDISequence?
    // Controls set these while SwiftUI is updating the view. Publishing more changes right
    // then is undefined behaviour (it can leave the window unresponsive), so the work each
    // one triggers runs on the next turn of the main run loop.
    @Published var rubricChoice: RubricChoice = .beginner {
        didSet { if rubricChoice != oldValue { DispatchQueue.main.async { [weak self] in self?.rubricChanged() } } }
    }
    @Published private(set) var rubricFileName: String?
    @Published private(set) var typing = MusicalTyping()
    @Published var soundOn = true
    /// Built-in piano loudness, 0–2 (1 = as the instrument comes). Remembered.
    @Published var pianoVolume: Double = PlaySession.storedVolume("piano", default: 1.4) {
        didSet {
            synth?.volume = pianoVolume
            UserDefaults.standard.set(pianoVolume, forKey: "PianoPad.volume.piano")
        }
    }
    /// Backing track loudness, 0–1. Remembered.
    @Published var backingVolume: Double = PlaySession.storedVolume("backing", default: 0.8) {
        didSet {
            backing?.volume = Float(backingVolume)
            UserDefaults.standard.set(backingVolume, forKey: "PianoPad.volume.backing")
        }
    }

    private static func storedVolume(_ name: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: "PianoPad.volume.\(name)") as? Double ?? value
    }
    @Published var showGuide = true

    /// Reference audition.
    @Published private(set) var isAuditioning = false
    @Published private(set) var auditionHeld: Set<Int> = []
    @Published var auditionSpeed: Double = 1.0

    /// Grade automatically once the guide reaches the end of the passage and the keys go quiet.
    @Published var autoGrade = true {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.autoGrade ? self.scheduleAutoGrade() : self.cancelAutoGrade()
            }
        }
    }
    @Published private(set) var autoGradePending = false
    static let autoGradeDelay = 1.5

    /// Keys currently down, from either input.
    @Published private(set) var held: Set<Int> = []
    /// Keys down that the guide did not expect.
    @Published private(set) var wrong: Set<Int> = []
    /// Reference notes played correctly so far in this take: every chord the guide has
    /// passed, plus the notes of the current chord already struck. Drawn green.
    @Published private(set) var playedNotes: [PlayedNote] = []
    /// What the guide expects next.
    @Published private(set) var expected: Set<Int> = []
    @Published private(set) var guideProgress = (done: 0, total: 0)

    @Published private(set) var report: GradeReport?

    /// The opened MIDI file written out as a score (nil while a book passage is open).
    @Published private(set) var score: Score?
    /// Changes whenever `score` is replaced, so views can cache its layout.
    @Published private(set) var scoreID = UUID()

    /// The open book and the passage being practised.
    @Published private(set) var book: LoadedBook?
    @Published private(set) var passage: PassageAnnotation?
    @Published private(set) var pageImage: NSImage?
    @Published private(set) var pageBounds: CGRect = .zero
    @Published var showWholePage = false
    /// Whether the fingering overlay is toggled on.
    @Published var showFingering = true
    /// Fingered notes analyzed from the transcribed music.
    @Published private(set) var fingeringNotes: [FingeredNote] = []

    var topStaffFingering: [Int] {
        fingeringNotes.filter { $0.hand == .right }.map(\.finger)
    }
    /// MIDI files to pick from alongside the book's passages: the bundled examples and
    /// files opened recently. (name, url)
    @Published var pieces: [(name: String, url: URL)] = []
    /// Where the playhead is, in quarter notes from the start of the reference.
    @Published private(set) var playheadQuarter: Double?
    /// Printed measures with at least one flagged mistake in the last graded take.
    @Published private(set) var mistakeMeasures: Set<Int> = []
    /// Staff lines of each printed measure on the book page (measure number → staves, top first):
    /// from the annotations when given, otherwise found in the page image.
    @Published private(set) var staffPlacements: [Int: [StaffPlacement]] = [:]
    @Published private(set) var noteCount = 0
    /// Bluetooth MIDI keyboards being listened to.
    @Published private(set) var midiSources: [String] = []
    /// MIDI sources present but ignored: virtual ports (Logic, IAC), USB and network.
    @Published private(set) var ignoredMIDISources: [String] = []
    /// Listen to an acoustic piano through the microphone.
    @Published var micOn = false {
        didSet {
            guard micOn != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.micOn ? self.startMic() : self.stopMic()
                self.judgeInput = nil
                self.configureJudge()
            }
        }
    }
    @Published private(set) var micLevel: Float = 0
    /// The noise gate in use (the level a note must reach to start), for the meter.
    @Published private(set) var micGateLevel: Float = 0
    /// Moves the measured gate up (stricter) or down, in dB. Remembered.
    // Audio devices: kept for this Mac (UserDefaults), not per learner. Pickers set these
    // during a view update, so the work each one triggers runs on the next turn.
    /// The input to listen to (an `AudioDeviceInfo.uid`); nil: the built-in microphone.
    @Published var inputDeviceUID: String? = UserDefaults.standard.string(forKey: "PianoPad.audio.inputUID") {
        didSet {
            guard inputDeviceUID != oldValue else { return }
            UserDefaults.standard.set(inputDeviceUID, forKey: "PianoPad.audio.inputUID")
            DispatchQueue.main.async { [weak self] in self?.inputDeviceChanged() }
        }
    }
    /// Where to play the piano sound, clicks and backing (a uid); nil: the system default output.
    @Published var outputDeviceUID: String? = UserDefaults.standard.string(forKey: "PianoPad.audio.outputUID") {
        didSet {
            guard outputDeviceUID != oldValue else { return }
            UserDefaults.standard.set(outputDeviceUID, forKey: "PianoPad.audio.outputUID")
            DispatchQueue.main.async { [weak self] in self?.outputDeviceChanged() }
        }
    }
    @Published private(set) var audioInputs: [AudioDeviceInfo] = []
    @Published private(set) var audioOutputs: [AudioDeviceInfo] = []
    /// How the last room-noise measurement went; nil until one finishes.
    @Published private(set) var noiseOutcome: NoiseOutcome?

    enum NoiseOutcome: Equatable {
        /// Gate set: notes start above `gateDB`; the room sat at `roomDB`.
        case set(gateDB: Double, roomDB: Double)
        /// Too noisy to set a gate.
        case tooNoisy(peakDB: Double)
        /// Nothing came in from the microphone.
        case silent
    }

    @Published var gateOffsetDB: Double = UserDefaults.standard.double(forKey: "PianoPad.mic.gateOffsetDB") {
        didSet {
            UserDefaults.standard.set(gateOffsetDB, forKey: "PianoPad.mic.gateOffsetDB")
            applyGate()
        }
    }
    /// The room's noise as last measured (calibration or Measure silence); nil: not measured,
    /// and the detector measures the room itself for a moment after the mic starts.
    @Published private(set) var roomNoise: RoomNoise?
    @Published private(set) var micName = ""
    /// Calibration in progress: the instruction to show (nil when not calibrating).
    @Published private(set) var calibrationPrompt: String?
    /// Calibration in progress: 0 quiet, 1 Middle C, 2 D, 3 E; nil otherwise. Lets setup
    /// pulse the key to play.
    @Published private(set) var calibrationStep: Int?
    /// How the last calibration went; nil until one finishes (cleared when another starts).
    @Published private(set) var calibrationOutcome: CalibrationOutcome?

    enum CalibrationOutcome: Equatable {
        /// Calibrated, and the room is quiet enough.
        case clear
        /// Calibrated, but the room's noise gate is high: soft notes may be missed.
        case noisy(gateDB: Double)
        /// Not calibrated; the reason, in words for the learner.
        case failed(String)

        var succeeded: Bool { if case .failed = self { return false } else { return true } }
    }

    /// When the app started, for the time-to-first-note measure.
    let launchedAt = Date()
    /// When setup (onboarding) opened, if it has this run.
    var setupStartedAt: Date?
    /// A calibration profile is saved and in use.
    @Published private(set) var isCalibrated = false
    @Published var message: String?

    // Play-along
    // Pickers set these during a view update, so the work they trigger runs on the next turn.
    @Published var mode: PracticeMode = .wait {
        didSet {
            guard mode != oldValue, !settingModeDirectly else { return }
            DispatchQueue.main.async { [weak self] in self?.modeChanged() }
        }
    }
    /// Playback speed as a percentage of the recording's tempo.
    @Published var tempoPercent: Double = 100 {
        didSet { if tempoPercent != oldValue { DispatchQueue.main.async { [weak self] in self?.tempoChanged() } } }
    }
    /// Click on every beat (applies from the next start or replay).
    @Published var metronomeOn = false { didSet { backing?.metronomeOn = metronomeOn } }
    @Published private(set) var playAlongState: PlayAlongState = .idle

    /// What happens when the judge decides too much was missed.
    enum MissMode: String, CaseIterable, Identifiable {
        /// Stop, then play the bar again (with a lead-in from the bar before).
        case replayBar
        /// Stop on the chord and wait until it is played, then carry on from there.
        case waitForNote
        var id: String { rawValue }
        var title: String { self == .replayBar ? "Replay bar" : "Wait for note" }
    }

    /// Per learner (see PlaySession+Learners.swift).
    @Published var missMode: MissMode = .replayBar {
        didSet {
            guard !applyingLearnerSettings else { return }
            learnerSettings.missMode = missMode.rawValue
            saveLearnerSettings()
        }
    }
    /// While in `.countIn`: true when the bar before is playing as a lead-in (a replay),
    /// false for a count-in click.
    @Published private(set) var isLeadIn = false

    /// How forgiving the play-along judge is. Applies at once, even mid-bar.
    enum Strictness: String, CaseIterable, Identifiable {
        case rubric, keepGoing, gentle, standard, strict, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rubric: return "Rubric default"
            case .keepGoing: return "Keep going (no replays)"
            case .gentle: return "Gentle"
            case .standard: return "Standard"
            case .strict: return "Strict"
            case .custom: return "Custom"
            }
        }
    }

    /// Per learner (see PlaySession+Learners.swift).
    @Published var strictness: Strictness = .rubric {
        didSet {
            guard strictness != oldValue, !applyingLearnerSettings else { return }
            learnerSettings.strictness = strictness.rawValue
            saveLearnerSettings()
            DispatchQueue.main.async { [weak self] in self?.configureJudge() }
        }
    }
    /// The Custom settings (edited with the sliders). Per learner.
    @Published var customPlayAlong: Rubric.PlayAlong = .gentle {
        didSet {
            guard customPlayAlong != oldValue, !applyingLearnerSettings else { return }
            learnerSettings.customPlayAlong = try? JSONEncoder().encode(customPlayAlong)
            saveLearnerSettings()
            if strictness == .custom { DispatchQueue.main.async { [weak self] in self?.configureJudge() } }
        }
    }
    /// Misses in the bar being played, and how many it may have.
    @Published private(set) var barMissCount: (count: Int, allowed: Int)?
    /// Bar the music is in (0-based, played order).
    @Published private(set) var playAlongBar: Int?
    @Published private(set) var playAlongBarCount = 0
    /// Times each bar (0-based) was played again in this take.
    @Published private(set) var rewindsPerBar: [Int: Int] = [:]
    /// The backing track's name; nil plays clicks only.
    @Published private(set) var backingName: String?
    /// The saved track linked to the open passage or MIDI file, if any.
    @Published private(set) var linkedTrackID: UUID?
    /// Which tab the window shows.
    @Published var tab: AppTab = .practice {
        didSet {
            // The tab bar sets this during a view update: react on the next turn of the run loop.
            if tab != oldValue { DispatchQueue.main.async { [weak self] in self?.tabChanged() } }
        }
    }

    enum AppTab: Hashable { case learn, practice, books, backingTracks }

    // PlaySession callbacks are main-thread-only. Keep the actor bridge at this boundary.
    private var earTrainingStorage: EarPracticeCoordinator?
    var earTraining: EarPracticeCoordinator {
        MainActor.assumeIsolated {
            if let earTrainingStorage { return earTrainingStorage }
            let output = AppEarSequenceOutput(
                start: { [weak self] in self?.startEarSequence($0) },
                position: { [weak self] in self?.earSequencePosition($0) },
                stop: { [weak self] in self?.stopEarSequence($0) })
            let playback = EarSequencedPlayback(output: output, isAuthorized: { [weak self] in
                self?.isEarTrainingActive == true && self?.isChoosingLearner == false
            })
            let coordinator = EarPracticeCoordinator(playback: playback)
            coordinator.bind(learnerID: learner?.id, history: learner.map { learnerStore.history(for: $0.id) })
            earTrainingStorage = coordinator
            return coordinator
        }
    }
    private var earSequenceLease: UUID?

    private func startEarSequence(_ notes: [NoteEvent]) -> UUID? {
        guard isEarTrainingActive, !isChoosingLearner else { return nil }
        if synth == nil { synth = PianoSynth(outputDeviceUID: outputDeviceUID); synth?.volume = pianoVolume }
        guard let synth else { return nil }
        let lease = UUID()
        earSequenceLease = lease
        guard synth.playSequence(notes.map { PianoSynth.SequenceNote(pitch: $0.pitch, velocity: $0.velocity,
                                                                     start: $0.onset, end: $0.offset) }) else {
            earSequenceLease = nil
            return nil
        }
        return lease
    }

    private func earSequencePosition(_ lease: UUID) -> Double? {
        earSequenceLease == lease ? synth?.sequencePosition : nil
    }
    private func stopEarSequence(_ lease: UUID) {
        guard earSequenceLease == lease else { return }
        synth?.stopSequence()
        earSequenceLease = nil
    }
    func prepareEarLesson(_ active: Bool) {
        if let lease = earSequenceLease { stopEarSequence(lease) }
        MainActor.assumeIsolated { earTraining.session.stop() }
        if active {
            stopAudition(); stopPlayAlong(discard: false)
            cancelAutoGrade(); settleWork?.cancel()
            keyPitch.removeAll(); mousePitch = nil
            held.removeAll(); wrong.removeAll()
            synth?.allNotesOff()
        }
        audio?.setMuted(active || isAuditioning)
    }

    func refreshEarLearner() {
        MainActor.assumeIsolated {
            earTraining.bind(learnerID: learner?.id, history: learner.map { learnerStore.history(for: $0.id) })
            if tab == .learn { lessonRunner.arrive() }
        }
    }
    func stopEarForLearnerChange() {
        MainActor.assumeIsolated { earTraining.close() }
    }
    func resetEarProgress(for id: UUID) {
        MainActor.assumeIsolated { earTraining.didReset(learnerID: id) }
    }

    /// Tabs where the keys play notes (typing and the on-screen keyboard).
    var isEarTrainingActive: Bool { tab == .learn && lessonRunner.shownBlock?.kind == .earTraining }
    var tabPlaysNotes: Bool { (tab == .practice || tab == .learn) && !isEarTrainingActive }

    /// Saved backing tracks and their links to passages.
    let backingStore = BackingStore()
    /// The Backing Tracks tab.
    lazy var backingEditor = BackingEditorModel(store: backingStore)
    /// The Books tab: reading a piece from a PDF music book.
    lazy var bookImport = BookImportModel(session: self)

    /// Plays one note (nudging a note while checking a piece read from a book).
    func previewPitch(_ pitch: Int) {
        synth?.play(pitch: pitch, velocity: 80, duration: 0.6)
    }

    /// Plays a few notes, scheduled from now (Listen on a bar being checked).
    func previewNotes(_ notes: [(pitch: Int, start: Double, length: Double)]) {
        guard let synth else { return }
        for n in notes {
            DispatchQueue.main.asyncAfter(deadline: .now() + n.start) {
                synth.play(pitch: n.pitch, velocity: 80, duration: n.length)
            }
        }
    }

    // MARK: Private state

    @Published var tutor: PiecePracticeEngine?
    @Published var tutorText = ""
    @Published var tutorAI = ""
    @Published var tutorBusy = false
    var tutorTask: Task<Void, Never>?
    var tutorGeneration = UUID()
    var tutorFullReference: MIDISequence?
    var tutorSavedSetup: PracticeSnapshot?
    var tutorBeforeAttempt: PiecePracticeEngine?
    var tutorAttempt: PracticeExercise?
    var tutorFeedbackClient: (any TutorFeedbackClient)?
    var tutorContext = ""
    var tutorRecent: [String] = []

    private var fileRubric: Rubric?
    /// The reference as read from the file. `reference` is this retimed to a linked backing
    /// track's tempo, so everything (listening, the score, grading) follows the backing.
    private var sourceReference: MIDISequence?
    /// Grade only from here (quarters): the take started partway through the piece.
    private var gradeFromQuarter: Double = 0
    private var notes: [NoteEvent] = []
    private var openNote: [Int: Int] = [:]        // pitch → index into notes
    private var takeStart: Double?
    private(set) var lastTake: [NoteEvent] = []
    private var keyPitch: [UInt16: Int] = [:]     // keyCode → pitch it started
    /// The source of the last note played; nil until one is (see `currentJudgeInput`).
    private var judgeInput: InputSource?
    /// The key the mouse is holding down on the on-screen keyboard.
    private var mousePitch: Int?

    // Lessons (see PlaySession+Lessons.swift)
    /// Told about notes, chords, listening and grades while a lesson drives the session.
    weak var lessonObserver: PlayerObserver?
    /// The lesson block loaded; nil outside lessons. Takes are saved under it, and play-along
    /// may run on clicks alone.
    var lessonPiece: PieceID?
    /// Count-in length for a lesson's timed block, in beats.
    var lessonCountInBeats = 4
    /// The practice setup to put back when the lesson ends.
    var practiceBeforeLesson: PracticeSnapshot?
    /// Set while a lesson changes `mode`, so the change applies at once (see `setModeNow`).
    var settingModeDirectly = false
    /// A lesson block's own play-along judging (nil: the learner's strictness).
    var lessonPlayAlong: Rubric.PlayAlong?
    /// Plays lesson pages in the Learn tab.
    lazy var lessonRunner = LessonRunner(player: self)
    /// Reference chords in order; the guide waits on each in turn.
    private var chords: [ChordEvent] = [] {
        didSet {
            settleWork?.cancel()
            guide = WaitGuide(chords: chords.map(\.pitches), settleWindow: rubric.chordWindowMs / 1000)
            rebuildJudge()
        }
    }
    private var guide = WaitGuide(chords: [])
    private var settleWork: DispatchWorkItem?
    private lazy var synth = PianoSynth(outputDeviceUID: outputDeviceUID)
    private var midi: MIDIInput?
    /// Kept while open so the Bluetooth MIDI window isn't released.
    private var bluetoothPairingWindow: CABTLEMIDIWindowController?
    private var audio: AudioInput?
    private var micLevelTimer: Timer?
    private var keyMonitor: Any?
    private var auditionWork: [DispatchWorkItem] = []
    private var auditionCount: [Int: Int] = [:]   // overlapping instances of a pitch
    private var autoGradeWork: DispatchWorkItem?
    private var auditionTimer: Timer?
    /// The preview under way: when it started and how its time maps to the music.
    private struct AuditionClock {
        var startedAt: TimeInterval
        var leadIn: Double
        var speed: Double
        var secondsPerQuarter: Double
        var firstQuarter: Double
        func quarter(atSeconds t: Double) -> Double { firstQuarter + max(0, t - leadIn) * speed / secondsPerQuarter }
    }
    private var auditionClock: AuditionClock?
    /// Note onsets in quarters, sorted: the playhead is published only when it reaches the
    /// next one, not every frame (the drawn playhead sits on the note anyway), so playback
    /// doesn't re-render the whole page 60 times a second.
    private var playheadSteps: [Double] = []

    // Play-along (main thread only)
    private var clock: BeatClock?
    private var judge: PlayAlongJudge?
    private var backing: BackingPlayer?
    private var backingURL: URL?
    private var backingAnnotation: BackingAnnotation?
    private var countInBars = 1
    private var anchor: PlaybackAnchor?
    private var playAlongTimer: Timer?
    private var rewindWork: DispatchWorkItem?
    private var warnedAboutSpeakers = false

    var rubric: Rubric {
        switch rubricChoice {
        case .beginner: return .beginner
        case .intermediate: return .intermediatePreset
        case .file: return fileRubric ?? .beginner
        }
    }

    // MARK: Setup

    // MARK: Learners (state; behaviour is in PlaySession+Learners.swift)

    let learnerStore: LearnerStore
    /// The learner whose settings, recent pieces and (later) takes are in use; nil until one is added.
    @Published var learner: Learner?
    @Published var learners: [Learner] = []
    /// True at launch when there is more than one learner, until someone picks who's playing.
    @Published var needsLearnerPick = false
    /// Ask whether to calibrate the mic (after adding the first learner on an uncalibrated Mac).
    @Published var offersCalibration = false
    /// The active learner's settings as last saved (or defaults when there is no learner).
    var learnerSettings = LearnerSettings()
    /// True while a learner's settings are being applied, so the property observers don't
    /// save them straight back.
    var applyingLearnerSettings = false
    /// Recent files this session holds security-scoped access to, by standardized path.
    var accessedRecentFiles: [String: URL] = [:]
    /// Active time per screen, for the anonymous usage stats (Usage.swift).
    private(set) var activity: ActivityTracker?

    init(learnerStore: LearnerStore = LearnerStore(), startServices: Bool = true) {
        self.learnerStore = learnerStore
        // Assigned directly (not through applyLearner), so no observers run during init.
        learners = learnerStore.learners
        learner = learnerStore.activeLearner
        needsLearnerPick = learners.count > 1
        learnerSettings = learner.map { learnerStore.settings(for: $0.id) } ?? LearnerSettings()
        strictness = Self.strictness(from: learnerSettings)
        customPlayAlong = Self.customPlayAlong(from: learnerSettings)
        missMode = Self.missMode(from: learnerSettings)
        synth?.volume = pianoVolume
        guard startServices else { return }
        try? LegacyTutorKeyMigration.run()
        startMIDI()
        // The learner's input choice (the mic back on for mic learners), once init is done.
        DispatchQueue.main.async { [weak self] in self?.applyInputChoice() }
        installKeyMonitor()
        backingStore.onTrackChanged = { [weak self] id in
            guard let self, self.linkedTrackID == id || self.linkedTrackID == nil else { return }
            if !self.isPlayingAlong { self.setupPlayAlong() }
        }
        // Load the bundled book (so its passages are in the picker), then open Ode to Joy;
        // fall back to the book's first passage, then the five-finger example.
        // SwiftUI creates the session while building the window, so publishing now would be
        // a change during a view update: load on the next turn of the run loop instead.
        DispatchQueue.main.async { [weak self] in self?.loadDefaults() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activity = ActivityTracker(session: self)
        }
    }

    // MARK: Pieces (MIDI files in the passage picker)

    /// The bundled example MIDI files; always listed after the learner's recent files.
    private(set) var examplePieces: [URL] = []

    /// Tag for the passage picker: "passage:<id>" or "file:<path>".
    var currentPieceTag: String {
        if let passage { return "passage:" + passage.id }
        if let url = referenceURL { return "file:" + url.standardizedFileURL.path }
        return ""
    }

    func selectPiece(_ tag: String) {
        if tag.hasPrefix("passage:") {
            selectPassage(String(tag.dropFirst("passage:".count)))
        } else if tag.hasPrefix("file:") {
            let url = URL(fileURLWithPath: String(tag.dropFirst("file:".count)))
            guard FileManager.default.fileExists(atPath: url.path) else {
                message = "\(url.lastPathComponent) isn't there any more."
                forgetPiece(url)
                return
            }
            loadReference(url)
        }
    }

    /// Where bundled folders (Books/, Examples/, Lessons/) are looked for. The packaged app
    /// (App/project.yml) carries them in its bundle. The Swift package executable has no
    /// bundle and Xcode runs it from DerivedData, so also look in the working directory and
    /// next to this source file (…/Sources/PianoPad/).
    static var resourceRoots: [URL] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [Bundle.main.resourceURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath), packageRoot]
            .compactMap { $0 }
    }

    /// The first bundled copy of `relativePath` (e.g. "Lessons/unit1"), if any.
    static func bundledResource(_ relativePath: String) -> URL? {
        resourceRoots.map { $0.appendingPathComponent(relativePath) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func loadDefaults() {
        let roots = Self.resourceRoots
        let fm = FileManager.default
        if let examples = roots.map({ $0.appendingPathComponent("Examples") }).first(where: { fm.fileExists(atPath: $0.path) }),
           let files = try? fm.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil) {
            // Ode to Joy first, then the rest by name; recorded test takes aren't pieces.
            examplePieces = files
                .filter { $0.pathExtension.lowercased() == "mid" && !$0.lastPathComponent.hasPrefix("take-") }
                .sorted { a, b in
                    let ao = a.lastPathComponent.hasPrefix("ode-to-joy"), bo = b.lastPathComponent.hasPrefix("ode-to-joy")
                    return ao != bo ? ao : a.lastPathComponent < b.lastPathComponent
                }
        }
        rebuildPieces()
        if let annotations = roots.map({ $0.appendingPathComponent("Books/learning-the-code-book1.annotations.json") })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            loadBook(annotations)
        }
        if let ode = roots.map({ $0.appendingPathComponent("Examples/ode-to-joy-c.mid") })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            loadReference(ode)
        } else if passage == nil,
           let example = roots.map({ $0.appendingPathComponent("Examples/five-finger.mid") })
            .first(where: { fm.fileExists(atPath: $0.path) }) {
            loadReference(example)
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func startMIDI() {
        do {
            if let midi {
                midi.connectAllSources()
            } else {
                // PerfectPiano hears a piano two ways: the microphone, or Bluetooth MIDI.
                midi = try MIDIInput(
                    policy: .bluetoothOnly,
                    onNoteOn: { [weak self] pitch, velocity, time in
                        self?.noteOn(pitch, velocity: velocity, time: time, playSound: false, source: .midi)
                    },
                    onNoteOff: { [weak self] pitch, time in
                        self?.noteOff(pitch, time: time)
                    }
                )
                midi?.onSourcesChanged = { [weak self] _ in self?.updateMIDISources() }
            }
            updateMIDISources()
        } catch {
            message = "MIDI unavailable: \(error)"
        }
    }

    private func updateMIDISources() {
        midiSources = midi?.sourceNames ?? []
        ignoredMIDISources = midi?.ignoredSourceNames ?? []
    }

    /// Opens a window to pair a Bluetooth MIDI piano. The packaged app shows macOS's own
    /// Bluetooth MIDI window; run from the Swift package (no Info.plist, so no Bluetooth
    /// permission text) it opens Audio MIDI Setup, whose MIDI Studio has the same window.
    func showBluetoothMIDIPairing() {
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil {
            let controller = bluetoothPairingWindow ?? CABTLEMIDIWindowController()
            bluetoothPairingWindow = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
            message = "In Audio MIDI Setup choose Window → Show MIDI Studio, then the Bluetooth button, and connect your piano."
        }
        startMIDI()
    }

    // MARK: Microphone

    private func startMic() {
        let input = audio ?? AudioInput(
            onNoteOn: { [weak self] pitch, time in
                self?.noteOn(pitch, velocity: 80, time: time, playSound: false, strict: false, source: .microphone)
            },
            onNoteOff: { [weak self] pitch, time in
                self?.noteOff(pitch, time: time)
            }
        )
        if audio == nil { input.profile = PlaySession.loadProfile() }
        input.preferredInputUID = inputDeviceUID
        input.setMuted(isEarTrainingActive || isAuditioning)
        isCalibrated = input.profile != nil
        audio = input
        roomNoise = Self.newestRoomNoise(profile: input.profile)
        applyGate()
        updateExpected()
        input.start { [weak self] error in
            guard let self else { return }
            if let error {
                self.message = "\(error)"
                self.micOn = false
                return
            }
            self.micName = input.deviceName
            self.message = nil
            self.micLevelTimer?.invalidate()
            self.micLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                let level = self.audio?.level ?? 0
                if abs(level - self.micLevel) > 0.002 { self.micLevel = level }
                let gate = self.audio?.gateLevel ?? 0
                if gate != self.micGateLevel { self.micGateLevel = gate }
            }
        }
    }

    // MARK: Audio devices

    /// Re-reads the Mac's inputs and outputs (call when a picker appears).
    func refreshAudioDevices() {
        audioInputs = AudioDevices.inputs()
        audioOutputs = AudioDevices.outputs()
    }

    /// The input in use: the chosen one if present, else the built-in microphone.
    var effectiveInput: AudioDeviceInfo? {
        inputDeviceUID.flatMap { AudioDevices.device(uid: $0) } ?? AudioDevices.builtInInput()
    }

    private func inputDeviceChanged() {
        audio?.preferredInputUID = inputDeviceUID
        noiseOutcome = nil
        // A new input means a new room level: listen again from scratch.
        guard micOn else { return }
        stopMic()
        startMic()
    }

    private func outputDeviceChanged() {
        synth?.setOutputDevice(uid: outputDeviceUID)
        // The backing player is built per piece; the next start uses the new output.
        if !isPlayingAlong { backing = nil }
    }

    // MARK: Calibration

    private var calibrationWork: [DispatchWorkItem] = []

    /// Guides the player through quiet, C4, D4 and E4 (about 10 s), then measures the piano.
    /// About 10 seconds: quiet, then C4, D4 and E4. `guided` words the prompts for someone
    /// who has never found Middle C (setup); otherwise they're terse (the ⋯ menu).
    func startCalibration(guided: Bool = false) {
        guard calibrationPrompt == nil else { return }
        if !micOn { micOn = true }
        calibrationPrompt = "Getting ready…"
        calibrationOutcome = nil
        let steps: [(Double, Int, String)] = guided ? [
            (0.8, 0, "Stay quiet for a moment…"),
            (2.3, 1, "Find the 2 black keys in the middle. Play the white key just left of them (Middle C) and let it ring."),
            (5.0, 2, "Now the next white key up (D)."),
            (7.7, 3, "And the next one (E)."),
        ] : [
            (0.8, 0, "Stay quiet…"),
            (2.3, 1, "Play middle C (C4) firmly and let it ring"),
            (5.0, 2, "Now D (D4)"),
            (7.7, 3, "Now E (E4)"),
        ]
        // Give the microphone a moment to start before keeping its audio.
        let begin = DispatchWorkItem { [weak self] in self?.audio?.startCapture() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: begin)
        calibrationWork = [begin]
        for (time, step, prompt) in steps {
            let work = DispatchWorkItem { [weak self] in
                self?.calibrationPrompt = prompt
                self?.calibrationStep = step
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
            calibrationWork.append(work)
        }
        let finish = DispatchWorkItem { [weak self] in self?.finishCalibration() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5, execute: finish)
        calibrationWork.append(finish)
    }

    func cancelCalibration() {
        calibrationWork.forEach { $0.cancel() }
        calibrationWork = []
        audio?.finishCapture { _, _ in }
        calibrationPrompt = nil
        calibrationStep = nil
    }

    func clearCalibration() {
        try? FileManager.default.removeItem(at: PlaySession.profileURL)
        audio?.profile = nil
        isCalibrated = false
        message = "Calibration cleared: using the generic piano model."
    }

    private func finishCalibration() {
        calibrationPrompt = "Measuring…"
        calibrationStep = nil
        audio?.finishCapture { [weak self] samples, rate in
            guard let self else { return }
            self.calibrationPrompt = nil
            self.calibrationWork = []
            // Capture starts as "Stay quiet…" shows and C4 is asked for 1.5 s later: measure the
            // room's noise inside that, clear of both edges.
            switch PianoCalibration.analyse(samples, sampleRate: rate, silence: 0.15..<1.35) {
            case .success(let profile):
                PlaySession.saveProfile(profile)
                self.audio?.profile = profile
                self.isCalibrated = true
                self.roomNoise = profile.roomNoise
                Self.saveRoomNoise(profile.roomNoise)
                self.applyGate()
                let gateDB = RoomNoise.dB(profile.roomNoise.gate)
                self.calibrationOutcome = gateDB > Self.noisyGateDB ? .noisy(gateDB: gateDB) : .clear
                self.message = String(format: "Calibrated: tuning %+.0f cents, noise gate %.0f dBFS. The mic now uses your piano's sound.",
                                      profile.tuningCents, gateDB)
            case .failure(let problem):
                self.calibrationOutcome = .failed(problem.description)
                self.message = "Calibration failed: \(problem)"
            }
        }
    }

    /// A noise gate above this (dBFS) means a noisy room: soft notes may not be heard.
    static let noisyGateDB = -45.0

    // MARK: Noise gate

    /// Re-measures only the room's noise (3 s of quiet) and sets the gate from it.
    func measureSilence() {
        guard calibrationPrompt == nil else { return }
        if !micOn { micOn = true }
        noiseOutcome = nil
        calibrationPrompt = "Getting ready…"
        let begin = DispatchWorkItem { [weak self] in
            self?.audio?.startCapture()
            self?.calibrationPrompt = "Stay quiet for 3 seconds…"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: begin)
        let finish = DispatchWorkItem { [weak self] in self?.finishMeasuringSilence() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.9, execute: finish)
        calibrationWork = [begin, finish]
    }

    private func finishMeasuringSilence() {
        calibrationPrompt = "Measuring…"
        audio?.finishCapture { [weak self] samples, rate in
            guard let self else { return }
            self.calibrationPrompt = nil
            self.calibrationWork = []
            let start = min(samples.count, Int(0.1 * rate))
            guard let room = RoomNoise.measure(samples[start...], sampleRate: rate) else {
                self.noiseOutcome = .silent
                self.message = "Couldn't hear the microphone. Is it on?"
                return
            }
            if room.isTooNoisy {
                self.noiseOutcome = .tooNoisy(peakDB: RoomNoise.dB(room.peak))
                self.message = String(format: "Too noisy to set a gate (%.0f dBFS). Try again in a quieter moment.", RoomNoise.dB(room.peak))
                return
            }
            self.roomNoise = room
            Self.saveRoomNoise(room)
            if var profile = self.audio?.profile {
                profile.update(room)
                Self.saveProfile(profile)
            }
            self.applyGate()
            self.noiseOutcome = .set(gateDB: RoomNoise.dB(room.gate), roomDB: RoomNoise.dB(room.median))
            self.message = String(format: "Noise gate set to %.0f dBFS (room %.0f dBFS). Notes start only above it.",
                                  RoomNoise.dB(room.gate), RoomNoise.dB(room.median))
        }
    }

    /// Gives the microphone the gate: the measured one moved by the offset, or none (the
    /// detector then measures the room itself when it starts).
    func applyGate() {
        audio?.noiseGate = roomNoise.map { RoomNoise.adjusted($0.gate, offsetDB: gateOffsetDB) }
    }

    /// The gate in dBFS with the offset, for display (nil when not measured).
    var gateDB: Double? { roomNoise.map { RoomNoise.dB(RoomNoise.adjusted($0.gate, offsetDB: gateOffsetDB)) } }

    private static var roomNoiseURL: URL { profileURL.deletingLastPathComponent().appendingPathComponent("room-noise.json") }

    private static func saveRoomNoise(_ room: RoomNoise) {
        let url = roomNoiseURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(room).write(to: url)
    }

    /// The most recent measurement: from "Measure silence" or from the calibration profile.
    private static func newestRoomNoise(profile: PianoProfile?) -> RoomNoise? {
        let saved = (try? Data(contentsOf: roomNoiseURL)).flatMap { try? JSONDecoder().decode(RoomNoise.self, from: $0) }
        switch (saved, profile?.roomNoise) {
        case let (s?, p?): return s.measured >= p.measured ? s : p
        case let (s?, nil): return s
        case let (nil, p?): return p
        case (nil, nil): return nil
        }
    }

    private static var profileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PianoPad/piano-profile.json")
    }

    private static func loadProfile() -> PianoProfile? {
        guard let data = try? Data(contentsOf: profileURL) else { return nil }
        return try? JSONDecoder().decode(PianoProfile.self, from: data)
    }

    private static func saveProfile(_ profile: PianoProfile) {
        let url = profileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(profile).write(to: url)
    }

    private func stopMic() {
        audio?.stop()
        micLevelTimer?.invalidate()
        micLevelTimer = nil
        micLevel = 0
        // Release anything the microphone was holding down.
        for pitch in held where wrong.contains(pitch) || !expected.contains(pitch) {
            noteOff(pitch, time: ProcessInfo.processInfo.systemUptime)
        }
    }

    // MARK: Computer keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// Returns true when the event was used (and should not reach the rest of the app).
    private func handleKey(_ event: NSEvent) -> Bool {
        // Leave ⌘-shortcuts (quit, close, open…) to the app.
        if event.modifierFlags.contains(.command) { return false }
        // Typing into a text field (track name, tempo…) isn't playing, and the backing-track
        // editor has its own keys. Key-ups still go through so no note is left hanging.
        if event.type == .keyDown && (!tabPlaysNotes || event.window?.firstResponder is NSText) { return false }
        // Nor is anything typed while choosing or adding a learner (the launch screens and sheets).
        if event.type == .keyDown && (isChoosingLearner || event.window?.isSheet == true) { return false }

        if event.type == .keyUp {
            guard let pitch = keyPitch.removeValue(forKey: event.keyCode) else { return false }
            noteOff(pitch, time: event.timestamp)
            return true
        }

        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            finishTake()
            return true
        case 53: // Escape
            if mode == .playAlong && isPlayingAlong {
                stopPlayAlong(discard: true)
            } else if isAuditioning {
                stopAudition()
            } else {
                discardTake()
            }
            return true
        case 49: // Space
            if !event.isARepeat { mode == .playAlong ? togglePlayAlong() : toggleAudition() }
            return true
        default:
            break
        }

        // A held key auto-repeats; the note is already sounding.
        if event.isARepeat { return keyPitch[event.keyCode] != nil }

        guard let byte = event.charactersIgnoringModifiers?.lowercased().utf8.first else { return false }
        switch typing.handle(byte) {
        case let .note(pitch, velocity):
            keyPitch[event.keyCode] = pitch
            noteOn(pitch, velocity: velocity, time: event.timestamp, playSound: true, source: .computerKeyboard)
            return true
        case .octave, .velocity:
            return true
        case .finish, .cancel, .ignored:
            return false
        }
    }

    func shiftOctave(_ delta: Int) {
        _ = typing.handle(UInt8(ascii: delta < 0 ? "z" : "x"))
    }

    // MARK: On-screen keyboard (mouse)

    /// The mouse went down on, or was dragged onto, `pitch`. Dragging across keys releases the
    /// last one and plays the next (a glissando). Counts as the computer keyboard for timing.
    func mouseDown(on pitch: Int) {
        guard tabPlaysNotes, !isChoosingLearner, pitch != mousePitch else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = mousePitch { noteOff(previous, time: now) }
        mousePitch = pitch
        noteOn(pitch, velocity: typing.velocity, time: now, playSound: true, source: .computerKeyboard)
    }

    /// The mouse was released, or dragged off the keys.
    func mouseUp() {
        guard let pitch = mousePitch else { return }
        mousePitch = nil
        noteOff(pitch, time: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: Notes

    /// - Parameter strict: whether a key outside the expected chord stops it passing (MIDI and
    ///   the computer keyboard). The microphone is lenient: it can hear keys that weren't played.
    /// - Parameter source: where the note came from; the play-along judge gives each its own
    ///   extra lateness, so it's reconfigured (before judging this note) when the source changes.
    private func noteOn(_ pitch: Int, velocity: Int, time: Double, playSound: Bool, strict: Bool = true,
                        source: InputSource) {
        guard tabPlaysNotes, !isChoosingLearner else { return }
        if tutor != nil && (tutorAttempt == nil || phase == .graded) { return }
        if source != judgeInput {
            judgeInput = source
            configureJudge()
        }
        lessonObserver?.playerNotePlayed(pitch, source: source)
        activity?.interacted()
        cancelAutoGrade()
        if isAuditioning { stopAudition() }
        if mode == .playAlong {
            playAlongNoteOn(pitch, velocity: velocity, time: time, playSound: playSound)
            return
        }
        if phase == .graded { resetTake() }
        if phase == .waiting {
            phase = .recording
            takeStart = time
        }
        if let i = openNote[pitch] { notes[i].offset = max(notes[i].onset, time) } // re-struck
        openNote[pitch] = notes.count
        notes.append(NoteEvent(pitch: pitch, onset: time, offset: time, velocity: velocity))
        noteCount = notes.count
        held.insert(pitch)
        if playSound && soundOn { synth?.noteOn(pitch: pitch, velocity: velocity) }
        advanceGuide(with: pitch, strict: strict)
    }

    private func noteOff(_ pitch: Int, time: Double) {
        // Other sections still drain key releases; the ear sequencer owns the sampler here.
        guard !isEarTrainingActive else { return }
        if let i = openNote.removeValue(forKey: pitch) {
            notes[i].offset = max(notes[i].onset + 0.01, time)
            if mode == .playAlong {
                notes[i].offsetBeats = max(notes[i].onsetBeats, anchor?.quarter(atUptime: time) ?? notes[i].onsetBeats + 0.25)
            }
        }
        held.remove(pitch)
        guide.noteOff(pitch)
        if mode == .playAlong { wrong.remove(pitch) } else { wrong = guide.wrongHeld }
        synth?.noteOff(pitch: pitch)
        scheduleAutoGrade()
    }

    // MARK: Auto-grade

    /// The take is complete when every reference chord has been played.
    var passageComplete: Bool { !chords.isEmpty && guide.isFinished }

    private func scheduleAutoGrade() {
        cancelAutoGrade()
        // Lessons always auto-grade: a wait block is done when its take is graded.
        guard mode == .wait, autoGrade || isInLesson || tutor != nil, phase == .recording, passageComplete, held.isEmpty else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.autoGrade || self.isInLesson || self.tutor != nil, self.phase == .recording, self.held.isEmpty else { return }
            self.finishTake()
        }
        autoGradeWork = item
        autoGradePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoGradeDelay, execute: item)
    }

    private func cancelAutoGrade() {
        autoGradeWork?.cancel()
        autoGradeWork = nil
        autoGradePending = false
    }

    // MARK: Guide

    /// Wait mode: a chord passes only when its notes are down and no wrong key is, and it has
    /// stayed that way for the chord window (keys struck together arrive a few ms apart).
    private func advanceGuide(with pitch: Int, strict: Bool) {
        guard !guide.isFinished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let chordIndex = guide.index
        let due = guide.noteOn(pitch, at: now, strict: strict)
        if guide.wrongHeld.contains(pitch) { lessonObserver?.playerWrongNote(onChord: chordIndex) }
        if let due {
            settleWork?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let waitingOn = self.guide.index
                if self.guide.settle(at: max(ProcessInfo.processInfo.systemUptime, due)) {
                    self.lessonObserver?.playerChordPlayed(waitingOn)
                    self.updateExpected()
                    self.scheduleAutoGrade()
                }
            }
            settleWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, due - now), execute: item)
        }
        wrong = guide.wrongHeld
        updateExpected()
    }

    private func updateExpected() {
        if mode == .playAlong {
            updatePlayAlongDisplay()
            return
        }
        expected = guide.expected
        // The microphone listens for the whole chord being waited for.
        let chord = guide.isFinished || guide.index >= chords.count ? [] : chords[guide.index].pitches
        if audio?.expected != chord { audio?.expected = chord }
        guideProgress = (guide.index, chords.count)
        var played: [PlayedNote] = []
        for chord in chords.prefix(guide.index) {
            for n in chord.notes { played.append(PlayedNote(quarter: n.onsetBeats, pitch: n.pitch)) }
        }
        if !guide.isFinished, guide.index < chords.count {
            for n in chords[guide.index].notes where guide.hit.contains(n.pitch) {
                played.append(PlayedNote(quarter: n.onsetBeats, pitch: n.pitch))
            }
        }
        if played != playedNotes { playedNotes = played }
        updatePlayhead()
    }

    /// Outside an audition the playhead sits on the next expected note (wait mode):
    /// it only moves when the right notes are played. Hidden once graded.
    private func updatePlayhead() {
        guard !isAuditioning, mode == .wait else { return }
        if phase == .graded || guide.isFinished || guide.index >= chords.count {
            playheadQuarter = nil
        } else {
            playheadQuarter = chords[guide.index].onsetBeats
        }
    }

    // MARK: Takes

    var canFinishTake: Bool { phase == .recording }

    func finishTake() {
        cancelAutoGrade()
        if mode == .playAlong {
            finishPlayAlongTake()
            return
        }
        guard phase == .recording, let start = takeStart else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for (_, i) in openNote { notes[i].offset = max(notes[i].onset + 0.01, now) }
        openNote = [:]
        synth?.allNotesOff()
        lastTake = notes.map { n in
            var m = n
            m.onset -= start
            m.offset -= start
            m.onsetBeats = m.onset * 2 // saved takes use 120 bpm
            return m
        }
        phase = .graded
        grade()
        recordGradedTake()
        reportGradeToLesson()
        tutorGraded()
        updatePlayhead()
    }

    func discardTake() {
        synth?.allNotesOff()
        resetTake()
    }

    /// The Reset button: stops listening or playing along, throws the take away and goes
    /// back to the start of the piece.
    func resetAll() {
        stopAudition()
        stopPlayAlong(discard: false)
        playAlongState = .idle
        discardTake()
        if mode == .playAlong { playheadQuarter = nil }
        message = nil
    }

    /// Something to reset: a take, a grade, the music running, or the guide moved on.
    var canReset: Bool {
        phase != .waiting || isPlayingAlong || isAuditioning || guideProgress.done > 0 || report != nil
            || !rewindsPerBar.isEmpty
    }

    func resetTake() {
        cancelAutoGrade()
        notes = []
        openNote = [:]
        takeStart = nil
        noteCount = 0
        report = nil
        mistakeMeasures = []
        settleWork?.cancel()
        guide.reset()
        judge?.reset()
        rewindsPerBar = [:]
        gradeFromQuarter = 0
        wrong = []
        phase = .waiting
        updateExpected()
    }

    private func grade() {
        guard let reference else {
            message = "Open a reference MIDI file to grade against."
            report = nil
            return
        }
        // A take started partway through is graded against the part that was played.
        var gradedReference = reference
        if gradeFromQuarter > 0 {
            gradedReference.notes = reference.notes.filter { $0.onsetBeats >= gradeFromQuarter - 1e-6 }
        }
        let graded = Grader(rubric: rubric).grade(reference: gradedReference, take: MIDISequence(notes: lastTake))
        report = graded
        // On a book page, printed measures (repeats map back); on a transcribed score the
        // grader's measure numbers are the score's own.
        mistakeMeasures = passage?.measuresWithMistakes(in: graded) ?? Set(graded.flags.map(\.position.measure))
    }

    private func rubricChanged() {
        if isPlayingAlong { stopPlayAlong(discard: true) }
        chords = reference.map { ChordGrouping.group($0.notes, window: rubric.chordWindowMs / 1000) } ?? []
        if phase == .graded { grade() } else { updateExpected() }
    }

    // MARK: Audition

    func toggleAudition() {
        if isAuditioning { stopAudition() } else { startAudition() }
    }

    /// Plays the reference through the built-in piano and lights its keys.
    /// Plays even with Sound off, since listening is the point.
    func startAudition() {
        guard let reference, let synth, !reference.notes.isEmpty else {
            if reference == nil { message = "Open a reference MIDI file first." }
            return
        }
        guard phase != .recording, !isPlayingAlong else { return }
        stopAudition()
        isAuditioning = true
        audio?.setMuted(true) // the speakers would be heard as playing

        let leadIn = 0.25
        let speed = max(0.1, auditionSpeed)
        let start = reference.notes.map(\.onset).min() ?? 0
        let notes = reference.notes.map { note in
            PianoSynth.SequenceNote(pitch: note.pitch, velocity: note.velocity,
                                    start: leadIn + (note.onset - start) / speed,
                                    end: leadIn + max(note.offset - start, note.onset - start + 0.05) / speed)
        }
        let end = notes.map(\.end).max() ?? leadIn

        // The notes play on the audio engine's clock, so a busy main thread can't make them
        // stutter. If that can't start, they're timed on the main thread as before.
        let onAudioClock = synth.playSequence(notes)
        if !onAudioClock {
            for note in notes {
                schedule(at: note.start) { [weak self] in
                    guard let self else { return }
                    if self.auditionCount[note.pitch, default: 0] > 0 { synth.noteOff(pitch: note.pitch) } // re-strike
                    synth.noteOn(pitch: note.pitch, velocity: note.velocity)
                    self.auditionCount[note.pitch, default: 0] += 1
                    self.auditionHeld.insert(note.pitch)
                }
                schedule(at: note.end) { [weak self] in
                    guard let self else { return }
                    let remaining = max(0, self.auditionCount[note.pitch, default: 1] - 1)
                    self.auditionCount[note.pitch] = remaining
                    if remaining == 0 {
                        synth.noteOff(pitch: note.pitch)
                        self.auditionHeld.remove(note.pitch)
                    }
                }
            }
        }

        // The playhead and lit keys follow the audio. The reference has one tempo, so time
        // maps linearly to quarter notes.
        let clock = AuditionClock(startedAt: ProcessInfo.processInfo.systemUptime, leadIn: leadIn, speed: speed,
                                  secondsPerQuarter: 60.0 / max(1, reference.initialTempoBPM),
                                  firstQuarter: reference.notes.map(\.onsetBeats).min() ?? 0)
        auditionClock = clock
        playheadSteps = Array(Set(reference.notes.map(\.onsetBeats))).sorted()
        publishPlayhead(clock.firstQuarter)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, let clock = self.auditionClock else { return }
            let t = (onAudioClock ? synth.sequencePosition : nil)
                ?? ProcessInfo.processInfo.systemUptime - clock.startedAt
            if onAudioClock {
                var sounding = Set<Int>()
                for n in notes where n.start <= t && t < n.end { sounding.insert(n.pitch) }
                if sounding != self.auditionHeld { self.auditionHeld = sounding }
            }
            self.publishPlayhead(clock.quarter(atSeconds: t))
            if t >= end + 0.1 {
                self.stopAudition()
                self.lessonObserver?.playerListenFinished()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        auditionTimer = timer
    }

    /// Where the preview is now, in quarters, for drawing that moves smoothly (the tempo
    /// line). Not published; nil when no preview is playing.
    func auditionQuarter(atUptime uptime: TimeInterval) -> Double? {
        guard isAuditioning, let clock = auditionClock else { return nil }
        return clock.quarter(atSeconds: uptime - clock.startedAt)
    }

    /// Sets the playhead, publishing only when it moves to another note. On a book page the
    /// playhead slides between notes, so it's set as is there.
    private func publishPlayhead(_ quarter: Double) {
        var shown = quarter
        if passage == nil {
            // The last onset at or before `quarter` (binary search); before the first, the beat.
            var lo = 0, hi = playheadSteps.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if playheadSteps[mid] <= quarter + 1e-6 { lo = mid + 1 } else { hi = mid }
            }
            shown = lo > 0 ? playheadSteps[lo - 1] : quarter.rounded(.down)
        }
        if playheadQuarter != shown { playheadQuarter = shown }
    }

    func stopAudition() {
        auditionWork.forEach { $0.cancel() }
        auditionWork = []
        if isAuditioning {
            synth?.stopSequence()
            for pitch in auditionHeld { synth?.noteOff(pitch: pitch) }
        }
        auditionClock = nil
        auditionHeld = []
        auditionCount = [:]
        auditionTimer?.invalidate()
        auditionTimer = nil
        isAuditioning = false
        if let audio {
            // Let the speakers' sound die away before listening again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.isAuditioning == false && self?.isEarTrainingActive == false { audio.setMuted(false) }
            }
        }
        updatePlayhead()
    }

    private func schedule(at seconds: Double, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        auditionWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: Files

    /// Loads a reference MIDI. A file chosen by hand no longer matches the page, so the
    /// passage is cleared unless the reference comes from the passage itself.
    /// A MIDI file opened on its own is transcribed into a score to play from; a passage's
    /// reference is shown on the book page instead.
    /// - Parameters:
    ///   - tempo: retime the file to this many quarter notes per minute (lessons set the tempo
    ///     per block); nil keeps the file's own.
    ///   - remember: add it to the learner's recent pieces (not for lesson files).
    /// `measures` keeps only those measures (1-based), moved to the start: a lesson's bar drill.
    /// `writtenScore` is shown instead of a transcription of the MIDI: pieces read from a book
    /// keep their own staves and clefs (Beyer writes both hands in treble clef).
    func loadReference(_ url: URL, keepPassage: Bool = false, tempo: Double? = nil, remember: Bool = true,
                       measures: ClosedRange<Int>? = nil, writtenScore: Score? = nil) {
        endTutoring()
        stopPlayAlong(discard: false)
        if !keepPassage {
            passage = nil
            staffPlacements = [:]
        }
        do {
            var sequence = try MIDIFile.read(url: url)
            sequence.notes.removeAll { $0.channel == 9 } // drums can't be played on the keys
            if let tempo, tempo > 0 { sequence = sequence.retimed(bpm: tempo) }
            if let measures { sequence = sequence.measures(measures) }
            stopAudition()
            sourceReference = sequence
            reference = sequence
            referenceURL = url
            chords = ChordGrouping.group(sequence.notes, window: rubric.chordWindowMs / 1000)
            score = keepPassage ? nil
                : writtenScore ?? Transcriber().transcribe(sequence, title: sequence.title ?? url.deletingPathExtension().lastPathComponent)
            scoreID = UUID()
            if let p = passage {
                fingeringNotes = PianoFingeringModel.analyze(passage: p, sequence: sequence)
            } else if let s = score {
                fingeringNotes = PianoFingeringModel.analyze(score: s)
            } else {
                fingeringNotes = PianoFingeringModel.analyze(sequence: sequence)
            }
            message = sequence.notes.isEmpty ? "\(url.lastPathComponent) has no notes to play." : nil
            if !keepPassage && remember { rememberPiece(url, title: sequence.title) }
            setupPlayAlong()
            resetTake()
        } catch {
            message = "Couldn't read \(url.lastPathComponent): \(error)"
        }
    }

    /// No passage, no MIDI: nothing to play against. Lesson explain blocks use this so their
    /// notes don't land on the previous block's music.
    func unloadReference() {
        endTutoring()
        stopAudition()
        stopPlayAlong(discard: true)
        passage = nil
        staffPlacements = [:]
        sourceReference = nil
        reference = nil
        referenceURL = nil
        chords = []
        fingeringNotes = []
        score = nil
        scoreID = UUID()
        setupPlayAlong()
        resetTake()
    }

    func chooseReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.midi]
        panel.message = "Choose a MIDI file to play"
        if panel.runModal() == .OK, let url = panel.url { loadReference(url) }
    }

    var canExportMusicXML: Bool { reference != nil }

    /// Saves the transcription of the current MIDI file (or passage reference) as MusicXML.
    func exportMusicXML() {
        guard let reference else { return }
        let stem = referenceURL?.deletingPathExtension().lastPathComponent ?? "score"
        let written = score ?? Transcriber().transcribe(reference, title: reference.title ?? stem)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "musicxml") ?? .xml]
        panel.nameFieldStringValue = "\(stem).musicxml"
        panel.message = "Save the transcription as MusicXML (opens in MuseScore, Dorico, Finale…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(MusicXMLWriter.write(written).utf8).write(to: url)
        } catch {
            message = "Couldn't save the MusicXML: \(error)"
        }
    }

    // MARK: Book

    func loadBook(_ annotationsURL: URL) {
        do {
            let annotations = try BookAnnotations.load(url: annotationsURL)
            let base = annotationsURL.deletingLastPathComponent()
            let pdfURL = base.appendingPathComponent(annotations.pdf).standardizedFileURL
            guard let document = PDFDocument(url: pdfURL) else {
                message = "Couldn't open \(annotations.pdf)."
                return
            }
            book = LoadedBook(annotations: annotations, baseURL: base, document: document)
            if let first = annotations.passages.first { selectPassage(first.id) }
        } catch {
            message = "Couldn't read \(annotationsURL.lastPathComponent): \(error)"
        }
    }

    func chooseBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a book's annotations file (.annotations.json)"
        if panel.runModal() == .OK, let url = panel.url { loadBook(url) }
    }

    func selectPassage(_ id: String) {
        endTutoring()
        guard let book, let p = book.annotations.passages.first(where: { $0.id == id }) else { return }
        renderPage(p.page, in: book.document)
        passage = p
        staffPlacements = findStaves(for: p)
        switch p.rubric {
        case "intermediate": rubricChoice = .intermediate
        case "beginner", nil: rubricChoice = .beginner
        default: break // a rubric file path: keep the current choice
        }
        loadReference(book.baseURL.appendingPathComponent(p.reference).standardizedFileURL, keepPassage: true)
    }

    private func renderPage(_ number: Int, in document: PDFDocument) {
        guard let page = document.page(at: number - 1) else {
            message = "The book has no page \(number)."
            pageImage = nil
            return
        }
        let bounds = page.bounds(for: .mediaBox)
        // Render at 3× so the score stays sharp when zoomed to the passage.
        pageImage = page.thumbnail(of: NSSize(width: bounds.width * 3, height: bounds.height * 3), for: .mediaBox)
        pageBounds = bounds
    }

    func chooseRubric() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["md", "yaml", "yml"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a rubric (Markdown with YAML front matter, or YAML)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            fileRubric = try Rubric.load(url: url)
            rubricFileName = url.lastPathComponent
            rubricChoice = .file
        } catch {
            message = "Couldn't read \(url.lastPathComponent): \(error)"
        }
    }

    var canSaveTake: Bool { phase == .graded && !lastTake.isEmpty }

    func saveTake() {
        guard canSaveTake else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        let stem = referenceURL?.deletingPathExtension().lastPathComponent ?? "take"
        panel.nameFieldStringValue = "\(stem)-take.mid"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MIDIFile.write(notes: lastTake).write(to: url)
        } catch {
            message = "Couldn't save the take: \(error)"
        }
    }

    // MARK: Played-note marks

    /// Wrong keys to mark on the staff: only while they are held (cleared on note-off).
    var markedWrong: Set<Int> { showGuide ? wrong : [] }

    /// Key used to write played notes: the score's, else the reference file's, else a guess.
    var noteKey: KeySignature {
        score?.key ?? reference?.keySignature ?? KeySignature.estimate(from: reference?.notes ?? [])
    }

    /// "You played E4 · play D4" while a wrong key is held.
    var wrongNoteHint: String? {
        let marked = markedWrong
        guard !marked.isEmpty else { return nil }
        let key = noteKey
        let played = marked.sorted().map { key.spell($0).name }.joined(separator: " ")
        let wanted = expected.sorted().map { key.spell($0).name }.joined(separator: " ")
        return wanted.isEmpty ? "You played \(played)" : "You played \(played) · play \(wanted)"
    }

    /// Staff lines for each measure of a passage: the annotation's own, or found in the page.
    private func findStaves(for passage: PassageAnnotation) -> [Int: [StaffPlacement]] {
        var result: [Int: [StaffPlacement]] = [:]
        let gray = pageImage.flatMap { Self.grayImage(from: $0) }
        for m in passage.measures {
            if let given = m.staff {
                result[m.number] = [given]
                continue
            }
            guard let gray, pageBounds.width > 0, pageBounds.height > 0 else { continue }
            let sx = Double(gray.width) / pageBounds.width
            let sy = Double(gray.height) / pageBounds.height
            // Search the middle of the measure, clear of clefs and barlines.
            let x0 = Int(((m.box.x + 0.1 * m.box.width) - pageBounds.minX) * sx)
            let x1 = Int(((m.box.maxX - 0.1 * m.box.width) - pageBounds.minX) * sx)
            let y0 = Int((pageBounds.maxY - m.box.maxY) * sy)
            let y1 = Int((pageBounds.maxY - m.box.y) * sy)
            let staves = StaffLineDetector.detect(in: gray, x0: x0, x1: x1, y0: y0, y1: y1)
            let placements = staves.map { staff in
                StaffPlacement(bottomLineY: pageBounds.maxY - staff.bottom / sy, spacing: staff.spacing / sy)
            }
            if !placements.isEmpty { result[m.number] = placements }
        }
        return result
    }

    /// The page image as greyscale pixels, top row first.
    private static func grayImage(from image: NSImage) -> GrayImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? GrayImage(width: width, height: height, pixels: pixels) : nil
    }

    // MARK: Display helpers

    /// Keyboard range: covers the typing keys and the reference, whole octaves, at least two.
    /// The on-screen keyboard: four octaves around Middle C (C2 to C6), always the same, so it
    /// doesn't jump when a note (or a stray detection) falls outside. Notes beyond it show as
    /// faint arrows at the ends.
    static let keyboardRange: ClosedRange<Int> = 36...84

    var displayRange: ClosedRange<Int> { Self.keyboardRange }

    /// Computer key for a pitch at the current octave, if any.
    func keyLabel(for pitch: Int) -> String? {
        let offset = pitch - typing.basePitch
        return MusicalTyping.noteKeys.first(where: { $0.value == offset }).map { String($0.key).uppercased() }
    }
}

// MARK: - Play-along

extension PlaySession {
    /// The music is running (counting in, playing, or pausing before a replay).
    var isPlayingAlong: Bool {
        switch playAlongState {
        case .countIn, .playing, .rewinding, .waitingForNote: return true
        case .idle, .finished: return false
        }
    }

    /// Play along needs a backing track: one linked to this piece (whose audio can be found),
    /// or one written into the book's annotations.
    var hasBackingTrack: Bool { backingURL != nil }

    /// Lessons may play along with clicks alone; the Practice tab needs a backing track.
    var canPlayAlong: Bool {
        reference != nil && clock != nil && (judge?.chordCount ?? 0) > 0 && (hasBackingTrack || lessonPiece != nil || tutor != nil)
    }

    /// Tempo heard at the current speed, in quarter notes per minute.
    var playAlongBPM: Double? { clock.map { $0.bpm * $0.tempoFactor } }

    /// The piece's tempo: the linked backing track's, else the MIDI file's.
    var originalBPM: Double? { clock?.bpm ?? reference?.initialTempoBPM }

    /// Where the music is right now, in quarters, while the play-along runs (the count-in
    /// included, before bar 1). Nil otherwise. For the tempo strip, read from the main thread.
    func liveQuarter(atUptime time: TimeInterval) -> Double? {
        guard playAlongState == .countIn || playAlongState == .playing, let anchor else { return nil }
        return anchor.quarter(atUptime: time)
    }

    /// The piece's meter, for the tempo strip (4/4 before anything is loaded).
    var meter: TimeSignature {
        clock?.timeSignature ?? reference?.timeSignature ?? TimeSignature(numerator: 4, denominator: 4)
    }

    /// Where the first bar starts, in quarters, so beat 1 lands on the downbeat.
    var firstBarQuarter: Double { clock?.barStart(0) ?? 0 }

    /// The bar a point in the music falls in (played order, from 0), where it starts and how
    /// long it is, in quarters; `pickup` when it's a short first bar. Nil before a piece's
    /// timing is loaded. For the child page's dancers, so their big jump lands on bar lines.
    func bar(containing quarter: Double) -> (index: Int, start: Double, length: Double, pickup: Bool)? {
        guard let clock else { return nil }
        let index = clock.barIndex(containing: quarter)
        let length = clock.barLength(index)
        return (index, clock.barStart(index), length, index == 0 && length < clock.quartersPerBar - 1e-6)
    }

    /// The practice tempo in bpm; setting it sets `tempoPercent`.
    var practiceBPM: Double {
        get { (originalBPM ?? 120) * tempoPercent / 100 }
        set {
            guard let original = originalBPM, original > 0, newValue > 0,
                  abs(newValue - practiceBPM) >= 0.05 else { return } // ignore the field's own rounding
            let percent = newValue / original * 100
            tempoPercent = min(Self.tempoRange.upperBound, max(Self.tempoRange.lowerBound, percent))
        }
    }

    static let tempoPresets: [Double] = [70, 80, 90, 100, 120, 150, 200]
    static let tempoRange: ClosedRange<Double> = 40...200

    /// "Bar 5: replayed 2×, bar 7: 1×" (played order, from 1).
    var rewindSummary: String? {
        guard !rewindsPerBar.isEmpty else { return nil }
        // Counts stops in wait-for-note mode, replays otherwise.
        return rewindsPerBar.keys.sorted()
            .map { "bar \(barLabel($0)): \(rewindsPerBar[$0]!)×" }
            .joined(separator: ", ")
    }

    /// A bar's number as printed (book passage) or counted from 1 (MIDI file).
    func barLabel(_ bar: Int) -> String {
        if let passage, let printed = passage.printedMeasure(forPlayed: bar + 1) { return "\(printed)" }
        return "\(bar + 1)"
    }

    /// The bar being replayed, as the score views number measures: printed numbers on a
    /// book page, played order from 1 on a transcribed score.
    var replayMeasure: Int? {
        guard case .rewinding(let bar) = playAlongState else { return nil }
        if let passage { return passage.printedMeasure(forPlayed: bar + 1) }
        return bar + 1
    }

    func togglePlayAlong() {
        isPlayingAlong ? stopPlayAlong(discard: true) : startPlayAlong()
    }

    /// Starts a take from the first bar.
    func startPlayAlong() { startPlayAlong(fromBar: 0) }

    /// Starts a take from bar `startBar` (0-based, played order): from the top with a
    /// count-in and the recording's intro, partway through with a lead-in bar.
    func startPlayAlong(fromBar startBar: Int) {
        guard mode == .playAlong, canPlayAlong, let clock else {
            if reference == nil {
                message = "Open a passage or MIDI file first."
            } else if !hasBackingTrack {
                message = "Missing backing track: link one to this piece with the waveform menu, or practise in Wait mode."
            }
            return
        }
        stopAudition()
        stopPlayAlong(discard: false)
        guard let player = makeBackingPlayer(clock: clock) else { return }
        // A lesson without a backing track keeps time with clicks all the way through.
        player.metronomeOn = metronomeOn || (lessonPiece != nil && !hasBackingTrack)
        player.setTempoFactor(clock.tempoFactor)
        if micOn && backingURL != nil && !warnedAboutSpeakers {
            warnedAboutSpeakers = true
            message = "Tip: use headphones with the mic, or it hears the backing track too."
        }
        resetTake()
        phase = .recording
        let bar = min(max(0, startBar), max(0, (judge?.barCount ?? 1) - 1))
        gradeFromQuarter = clock.barStart(bar)
        beginAttempt(atBar: bar, fresh: bar == 0)
    }

    /// Stops the music. With `discard`, the take is thrown away; otherwise it's kept for grading.
    func stopPlayAlong(discard: Bool) {
        rewindWork?.cancel()
        rewindWork = nil
        backing?.stop()
        playAlongTimer?.invalidate()
        playAlongTimer = nil
        anchor = nil
        let wasRunning = isPlayingAlong
        playAlongState = .idle
        playAlongBar = nil
        barMissCount = nil
        if discard && wasRunning { discardTake() }
        if mode == .playAlong { playheadQuarter = nil }
    }

    // MARK: Setup

    /// Builds the clock (and forgets any player) for the current reference and passage.
    func setupPlayAlong() {
        backing = nil
        backingURL = nil
        backingName = nil
        backingAnnotation = nil
        countInBars = 1
        linkedTrackID = backingLinkKey.flatMap { backingStore.linkedTrackID(for: $0) }
        guard let reference else {
            clock = nil
            rebuildJudge()
            return
        }
        if tutor != nil {
            clock = BeatClock(startSeconds: 0, bpm: reference.initialTempoBPM,
                              timeSignature: reference.timeSignature, tempoFactor: tempoPercent / 100)
            rebuildJudge()
            return
        }
        let factor = tempoPercent / 100
        // A saved track linked here wins over a backing written into the book's annotations.
        var chosen: BackingAnnotation?
        if let track = backingStore.track(linkedTrackID) {
            if let audio = backingStore.audioURL(for: track) {
                chosen = track.annotation(audioPath: audio.path)
                backingURL = audio
                backingName = track.name
            } else {
                message = "Can't find the audio for “\(track.name)” (\(URL(fileURLWithPath: track.audioPath).lastPathComponent)). Playing along with clicks."
            }
        } else if let passage, let book, let annotated = passage.backing {
            chosen = annotated
            backingURL = book.baseURL.appendingPathComponent(annotated.file).standardizedFileURL
            backingName = backingURL?.lastPathComponent
        }
        if let annotated = chosen {
            backingAnnotation = annotated
            countInBars = max(0, annotated.countInBars ?? 1)
            clock = BeatClock(startSeconds: annotated.startSeconds, bpm: annotated.bpm,
                              timeSignature: annotated.timeSignature, barLengths: passage?.playedBarLengths ?? [],
                              tempoFactor: factor)
            if annotated.timeSignature != reference.timeSignature && passage == nil {
                let a = annotated.timeSignature, r = reference.timeSignature
                message = "The backing track is in \(a.numerator)/\(a.denominator) but the MIDI file is in \(r.numerator)/\(r.denominator): bars follow the backing."
            }
            applyReferenceTempo(annotated.bpm)
        } else {
            applyReferenceTempo(nil)
            let ref = self.reference ?? reference
            clock = BeatClock(startSeconds: 0, bpm: ref.initialTempoBPM, timeSignature: ref.timeSignature,
                              barLengths: passage?.playedBarLengths ?? [], tempoFactor: factor)
        }
        rebuildJudge()
    }

    /// The piece takes the backing track's tempo (nil: back to the file's own).
    private func applyReferenceTempo(_ bpm: Double?) {
        guard let source = sourceReference else { return }
        let target = bpm.map { source.retimed(bpm: $0) } ?? source
        guard target.initialTempoBPM != reference?.initialTempoBPM || target.notes != reference?.notes else { return }
        stopAudition()
        reference = target
        // Chord grouping works in seconds, so group again at the new tempo.
        chords = ChordGrouping.group(target.notes, window: rubric.chordWindowMs / 1000)
        if score != nil { score?.tempoBPM = target.initialTempoBPM }
        if phase == .graded { grade() }
    }

    /// The file's own tempo, before any backing track's.
    var fileBPM: Double? { sourceReference?.initialTempoBPM }

    /// Where the judge assumes notes come from: the last note's source, or before any note,
    /// the microphone when it's on.
    var currentJudgeInput: InputSource { judgeInput ?? (micOn ? .microphone : .midi) }

    func rebuildJudge() {
        guard let clock, !chords.isEmpty else {
            judge = nil
            playAlongBarCount = 0
            return
        }
        judge = PlayAlongJudge(chords: chords, clock: clock, settings: playAlongSettings.judgeSettings(input: currentJudgeInput))
        playheadSteps = judge!.chordQuarters.sorted()
        playAlongBarCount = judge?.barCount ?? 0
    }

    /// New windows (rubric or mic changed) or tempo, keeping what's been played.
    func configureJudge() {
        guard let clock else { return }
        judge?.configure(settings: playAlongSettings.judgeSettings(input: currentJudgeInput),
                         secondsPerQuarter: clock.secondsPerQuarter)
    }

    private func makeBackingPlayer(clock: BeatClock) -> BackingPlayer? {
        if let backing { return backing }
        do {
            if let annotation = backingAnnotation, let url = backingURL {
                backing = try BackingPlayer(annotation: annotation, fileURL: url, clock: clock, outputDeviceUID: outputDeviceUID)
            } else if lessonPiece != nil || tutor != nil {
                // Lessons only: clicks, with a count-in of the block's beats (whole bars).
                let beatsPerBar = max(1, clock.timeSignature.numerator)
                let bars = max(1, Int((Double(lessonCountInBeats) / Double(beatsPerBar)).rounded(.up)))
                backing = try BackingPlayer(fileURL: nil, clock: clock, countInBars: bars, outputDeviceUID: outputDeviceUID)
            } else {
                // The Practice tab has no clicks-only fallback: play along has a backing track.
                message = "Missing backing track: link one to this piece with the waveform menu."
                return nil
            }
        } catch {
            message = "\(error)"
            return nil
        }
        backing?.volume = Float(backingVolume)
        backing?.onInterrupted = { [weak self] in
            self?.stopPlayAlong(discard: false)
            self?.message = "Playback stopped: the audio output changed."
        }
        if backing == nil { message = "Couldn't start audio playback." }
        return backing
    }

    // MARK: Running

    /// Starts the music for an attempt at `bar`.
    ///
    /// Replays start one bar early with the music playing (a lead-in) and judge only from
    /// `bar`. A count-in click is used instead where there is no bar before to play: the
    /// first bar, a bar before the recording's trim start, or with no recording (clicks only).
    /// A fresh start from the top also plays the recording's intro.
    private func beginAttempt(atBar bar: Int, fresh: Bool = false) {
        guard let backing, judge != nil else { return }
        judge!.rewind(toBar: bar)
        let leadIn = !fresh && bar > 0 && backing.hasAudio(forBar: bar - 1)
        // Keep clicking to the end of the music with notes in it.
        if leadIn {
            anchor = backing.play(fromBar: bar - 1, countIn: 0, until: judge!.endQuarter, includeIntro: false)
        } else {
            anchor = backing.play(fromBar: bar, until: judge!.endQuarter, includeIntro: fresh)
        }
        isLeadIn = leadIn
        playAlongState = .countIn
        playAlongBar = bar
        playAlongTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.playAlongTick() }
        RunLoop.main.add(timer, forMode: .common) // keep ticking while a slider is dragged
        playAlongTimer = timer
        updatePlayAlongDisplay()
    }

    /// Runs 60 times a second on the main thread: moves the playhead and lets the judge
    /// close chords whose time has passed.
    private func playAlongTick() {
        guard let anchor, let clock, judge != nil else { return }
        let q = anchor.quarter(atUptime: ProcessInfo.processInfo.systemUptime)
        let barStart = clock.barStart(judge!.startBar)
        if q < barStart {
            if playAlongState != .countIn { playAlongState = .countIn }
            // A lead-in bar moves the playhead through it; a count-in holds it on the bar.
            let shown = isLeadIn ? max(clock.barStart(max(0, judge!.startBar - 1)), q) : barStart
            publishPlayhead(shown)
        } else {
            if playAlongState != .playing { playAlongState = .playing }
            publishPlayhead(min(q, judge!.endQuarter))
            let bar = clock.barIndex(containing: q)
            if playAlongBar != bar { playAlongBar = bar }
        }
        // Notes reach the main thread a little after they're played (more from the mic), so
        // judge a moment behind the music rather than closing a chord a note is on its way to.
        let delivery = micOn ? 0.15 : 0.04
        let verdict = judge!.advance(toQuarter: q - delivery / anchor.secondsPerQuarter)
        switch verdict {
        case .onTrack:
            updatePlayAlongDisplay()
            if playAlongState == .playing, let bar = playAlongBar {
                let m = judge!.misses(inBar: bar)
                if barMissCount?.count != m.count || barMissCount?.allowed != m.allowed { barMissCount = m }
            }
        case .rewind(let bar):
            if missMode == .waitForNote, let chord = judge?.lastMissedChord {
                waitForNote(chord: chord)
            } else {
                replay(bar: bar)
            }
        case .finished:
            finishPlayAlongTake()
        }
    }

    /// Too many misses: stop, show the bar, then count in and play it again.
    private func replay(bar: Int) {
        backing?.stop()
        playAlongTimer?.invalidate()
        playAlongTimer = nil
        anchor = nil
        rewindsPerBar[bar, default: 0] += 1
        playAlongState = .rewinding(bar: bar)
        lessonObserver?.playerBarReplayed()
        if let clock { discardTakeNotes(fromQuarter: clock.barStart(bar)) }
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .rewinding = self.playAlongState else { return }
            self.beginAttempt(atBar: bar)
        }
        rewindWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    /// Wait-for-note mode: stop the music on `chord` until it is played.
    private func waitForNote(chord: Int) {
        guard judge != nil else { return }
        backing?.stop()
        playAlongTimer?.invalidate()
        playAlongTimer = nil
        anchor = nil
        let bar = judge!.chordBars[chord]
        rewindsPerBar[bar, default: 0] += 1
        judge!.waitOn(chord: chord)
        playAlongState = .waitingForNote(chord: chord, bar: bar)
        lessonObserver?.playerBarReplayed()
        playAlongBar = bar
        playheadQuarter = judge!.chordQuarters[chord]
        updatePlayAlongDisplay()
    }

    /// The awaited chord was played: carry on from it, straight away.
    private func resumeAfterWaiting(chord: Int) {
        guard let backing, let clock, judge != nil else { return }
        let q = judge!.chordQuarters[chord]
        let a = backing.play(fromAudioSeconds: clock.audioSeconds(atQuarter: q), clicks: metronomeOn)
        anchor = a
        isLeadIn = false
        playAlongState = .playing
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.playAlongTick() }
        RunLoop.main.add(timer, forMode: .common)
        playAlongTimer = timer
        updatePlayAlongDisplay()
    }

    /// Speed changed: re-time the windows and, if the music is running, replay the current bar.
    func tempoChanged() {
        let factor = max(0.25, min(2, tempoPercent / 100))
        clock?.tempoFactor = factor
        backing?.setTempoFactor(factor)
        configureJudge()
        guard isPlayingAlong, let judge, let backing else { return }
        // Stopped on a note: the new speed applies when it's played.
        if case .waitingForNote = playAlongState { return }
        let bar = playAlongBar.map { min($0, max(0, judge.barCount - 1)) } ?? judge.startBar
        rewindWork?.cancel()
        backing.stop()
        if let clock { discardTakeNotes(fromQuarter: clock.barStart(bar)) }
        beginAttempt(atBar: bar)
    }

    func modeChanged() {
        stopAudition()
        stopPlayAlong(discard: false)
        discardTake()
        if mode == .playAlong && clock == nil { setupPlayAlong() }
        wrong = []
        updateExpected()
        updatePlayhead()
    }

    // MARK: Notes

    func playAlongNoteOn(_ pitch: Int, velocity: Int, time: Double, playSound: Bool) {
        held.insert(pitch)
        if playSound && soundOn { synth?.noteOn(pitch: pitch, velocity: velocity) }
        // Stopped on a chord: judge keys at the chord's own time; carry on once it's played.
        if case .waitingForNote(let chord, _) = playAlongState, judge != nil {
            let q = judge!.chordQuarters[chord]
            let matchedWhileWaiting = judge!.noteOn(pitch, atQuarter: q)
            lessonObserver?.playerPlayAlongNote(matched: matchedWhileWaiting)
            if matchedWhileWaiting {
                if let i = openNote[pitch] { notes[i].offset = max(notes[i].onset, time); notes[i].offsetBeats = q }
                openNote[pitch] = notes.count
                notes.append(NoteEvent(pitch: pitch, onset: time, offset: time, velocity: velocity, onsetBeats: q))
                noteCount = notes.count
            } else {
                wrong.insert(pitch)
            }
            if judge!.states[chord] == .hit { resumeAfterWaiting(chord: chord) } else { updatePlayAlongDisplay() }
            return
        }
        guard let anchor, let clock, judge != nil, playAlongState == .countIn || playAlongState == .playing else { return }
        let q = anchor.quarter(atUptime: time)
        // Keys during the count-in or lead-in (before the bar's early window) aren't judged
        // and aren't part of the take: playing along with the bar before is fine.
        let earliest = clock.barStart(judge!.startBar) - judge!.settings.earlySeconds / anchor.secondsPerQuarter
        guard q >= earliest else {
            updatePlayAlongDisplay()
            return
        }
        let matched = judge!.noteOn(pitch, atQuarter: q)
        if !matched { wrong.insert(pitch) }
        lessonObserver?.playerPlayAlongNote(matched: matched)
        do {
            if let i = openNote[pitch] { // re-struck without a release
                notes[i].offset = max(notes[i].onset, time)
                notes[i].offsetBeats = max(notes[i].onsetBeats, q)
            }
            openNote[pitch] = notes.count
            notes.append(NoteEvent(pitch: pitch, onset: time, offset: time, velocity: velocity, onsetBeats: q))
            noteCount = notes.count
        }
        updatePlayAlongDisplay()
    }

    /// Forgets the take's notes from `quarter` on (that bar is being played again).
    private func discardTakeNotes(fromQuarter quarter: Double) {
        var kept: [NoteEvent] = []
        var newIndex: [Int: Int] = [:]
        for (i, n) in notes.enumerated() where n.onsetBeats < quarter {
            newIndex[i] = kept.count
            kept.append(n)
        }
        notes = kept
        openNote = openNote.compactMapValues { newIndex[$0] }
        noteCount = notes.count
    }

    /// Green notes, expected keys and progress from the judge.
    func updatePlayAlongDisplay() {
        guard let judge else {
            if !expected.isEmpty { expected = [] }
            if !playedNotes.isEmpty { playedNotes = [] }
            guideProgress = (0, 0)
            return
        }
        let next = judge.expected.asSet
        if next != expected { expected = next }
        let listenFor = judge.nextChordIndex.map { judge.chordPitches[$0].asSet } ?? []
        if audio?.expected != listenFor { audio?.expected = listenFor }
        var played: [PlayedNote] = []
        var hits = 0
        for i in 0..<min(chords.count, judge.chordCount) {
            if judge.states[i] == .hit { hits += 1 }
            let struck = judge.struck[i]
            guard !struck.isEmpty else { continue }
            for n in chords[i].notes where struck.contains(n.pitch) {
                played.append(PlayedNote(quarter: n.onsetBeats, pitch: n.pitch))
            }
        }
        if played != playedNotes { playedNotes = played }
        if guideProgress.done != hits || guideProgress.total != judge.chordCount {
            guideProgress = (hits, judge.chordCount)
        }
    }

    // MARK: Click a bar

    /// A bar was clicked on the score (0-based, played order). Play along: play from it,
    /// seeking the backing track (also while already playing). Wait: the guide waits there.
    func playFrom(bar: Int) {
        guard tutor == nil else { return }
        guard reference != nil else { return }
        if isAuditioning { stopAudition() }
        switch mode {
        case .playAlong:
            startPlayAlong(fromBar: bar) // says what's missing if it can't start
        case .wait:
            guard let clock else { return }
            let target = clock.barStart(bar)
            let index = chords.firstIndex { $0.onsetBeats >= target - 1e-6 } ?? chords.count
            discardTake()
            guide.jump(to: index)
            gradeFromQuarter = target
            updateExpected()
        }
    }

    /// A printed measure was clicked on the book page. With repeats it is played more than
    /// once: pick the next time it comes round after where the music is, else the first.
    func playFrom(printedMeasure number: Int) {
        guard let passage else { return }
        let order = passage.order
        let current = playAlongBar ?? -1
        let times = order.indices.filter { order[$0] == number }
        guard let first = times.first else { return }
        playFrom(bar: times.first(where: { $0 > current }) ?? first)
    }

    // MARK: Strictness

    /// The judge's settings: the chosen preset, or the rubric's.
    var playAlongSettings: Rubric.PlayAlong {
        if tutor != nil { return .keepGoing }
        // A lesson stage (a song's Perform) can set its own, without touching the learner's.
        if let lessonPlayAlong { return lessonPlayAlong }
        switch strictness {
        case .rubric: return rubric.playAlong
        case .keepGoing: return .keepGoing
        case .gentle: return .gentle
        case .standard: return .standard
        case .strict: return .strict
        case .custom: return customPlayAlong
        }
    }

    /// Starts Custom from whatever is in use now, so the sliders open where the judge is.
    func beginCustomStrictness() {
        guard strictness != .custom else { return }
        customPlayAlong = playAlongSettings
        strictness = .custom
    }

    static func strictness(from settings: LearnerSettings) -> Strictness {
        Strictness(rawValue: settings.strictness) ?? .rubric
    }

    static func customPlayAlong(from settings: LearnerSettings) -> Rubric.PlayAlong {
        guard let data = settings.customPlayAlong,
              let value = try? JSONDecoder().decode(Rubric.PlayAlong.self, from: data) else { return .gentle }
        return value
    }

    static func missMode(from settings: LearnerSettings) -> MissMode {
        MissMode(rawValue: settings.missMode) ?? .replayBar
    }

    // MARK: Backing-track links

    /// What a saved backing track is linked to: the open book passage, else the MIDI file.
    var backingLinkKey: String? {
        if let passage, let book { return BackingLinkKey.passage(book: book.annotations.pdf, id: passage.id) }
        return referenceURL.map { BackingLinkKey.reference(path: $0.standardizedFileURL.path) }
    }

    /// Links a saved track (nil: none) to the open passage or MIDI file.
    func linkBackingTrack(_ id: UUID?) {
        guard let key = backingLinkKey else { return }
        stopPlayAlong(discard: false)
        do {
            try backingStore.link(key, to: id)
            message = nil
        } catch {
            message = "Couldn't save the link: \(error.localizedDescription)"
        }
        setupPlayAlong()
    }

    func tabChanged() {
        // Invalidate a lease before stopping other players. A disappearing ear view's late
        // Stop can then never silence the new tab's sequence.
        if let lease = earSequenceLease { stopEarSequence(lease) }
        MainActor.assumeIsolated { earTraining.session.stop() }
        endTutoring()
        // Leaving a tab stops the music; coming back to practice picks up edits to the linked track.
        stopAudition()
        stopPlayAlong(discard: false)
        // Leaving Learn ends the lesson and puts the practice piece back.
        if tab != .learn { lessonRunner.leave() }
        audio?.setMuted(isEarTrainingActive || isAuditioning)
        switch tab {
        case .practice:
            backingEditor.stopPreview()
            setupPlayAlong()
        case .books:
            backingEditor.stopPreview()
        case .backingTracks:
            if backingEditor.draft == nil, let linked = backingStore.track(linkedTrackID) {
                // Open the editor on the track the current piece uses.
                backingEditor.select(linked.id)
            }
        case .learn:
            backingEditor.stopPreview()
            lessonRunner.arrive()
        }
    }

    // MARK: Grading

    /// Ends the take and grades it: each bar as last played (replayed bars replace earlier tries),
    /// with times taken from the beat so the speed played at doesn't count against the player.
    func finishPlayAlongTake() {
        let endQuarter = anchor.map { $0.quarter(atUptime: ProcessInfo.processInfo.systemUptime) }
        let wasRecording = phase == .recording
        stopPlayAlong(discard: false)
        guard wasRecording else { return }
        playAlongState = .finished
        synth?.allNotesOff()
        guard !notes.isEmpty || tutor != nil else {
            phase = .waiting
            return
        }
        let secondsPerQuarter = 60 / max(1, reference?.initialTempoBPM ?? 120)
        for (_, i) in openNote {
            notes[i].offsetBeats = max(notes[i].onsetBeats + 0.05, endQuarter ?? notes[i].onsetBeats + 1)
        }
        openNote = [:]
        lastTake = notes.map { n in
            var m = n
            let off = max(n.offsetBeats ?? n.onsetBeats + 0.25, n.onsetBeats + 0.02)
            m.onset = n.onsetBeats * secondsPerQuarter
            m.offset = off * secondsPerQuarter
            m.offsetBeats = off
            return m
        }
        .sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
        phase = .graded
        grade()
        recordGradedTake()
        reportGradeToLesson()
        tutorGraded()
        playheadQuarter = nil
    }
}

extension PlaySession {
    var tutorOffset: Double {
        guard let exercise = tutorAttempt, let full = tutorFullReference else { return 0 }
        return Double(exercise.measures.lowerBound - 1) * Double(full.timeSignature.numerator) * 4 / Double(full.timeSignature.denominator)
    }
    var tutorDisplayReport: GradeReport? {
        guard var report else { return nil }
        guard tutor != nil, let attempt = tutorAttempt else { return report }
        for i in report.flags.indices {
            let local = report.flags[i].position.measure
            report.flags[i].position.measure = passage?.printedMeasure(forPlayed: attempt.originalMeasure(local)) ?? attempt.originalMeasure(local)
            let oldPrefix = "m\(local) "
            report.flags[i].message = report.flags[i].message.replacingOccurrences(of: oldPrefix, with: "m\(report.flags[i].position.measure) ")
        }
        for i in report.results.indices {
            let local = report.results[i].position.measure
            report.results[i].position.measure = passage?.printedMeasure(forPlayed: attempt.originalMeasure(local)) ?? attempt.originalMeasure(local)
        }
        return report
    }
    var tutorPlayedNotes: [PlayedNote] { playedNotes.map { PlayedNote(quarter: $0.quarter + tutorOffset, pitch: $0.pitch) } }
    var tutorPlayhead: Double? { playheadQuarter.map { $0 + tutorOffset } }
    var tutorHighlight: Set<Int> {
        guard tutor != nil, let e = tutorAttempt else { return [] }
        return Set(e.measures.map { passage?.printedMeasure(forPlayed: $0) ?? $0 })
    }
    func beginTutoring() {
        guard tutor == nil, let reference, !reference.notes.isEmpty else { return }
        resetAll()
        tutorFullReference = sourceReference ?? reference
        tutorSavedSetup = PracticeSnapshot(mode: mode, tempoPercent: tempoPercent, metronomeOn: metronomeOn, pieceTag: currentPieceTag)
        let persona = learnerSettings.persona == "kriti" ? Persona.kriti : Persona.alex
        tutor = PiecePracticeEngine(measureCount: reference.measureCount, persona: persona)
        tutorText = "Try the piece so I can find what to practise. You can hear it first or learn the notes."
        tutorRecent = []; tutorContext = ""; tutorBeforeAttempt = nil; tutorAI = ""
    }
    func endTutoring() {
        guard tutor != nil else { return }
        tutorGeneration = UUID(); tutorTask?.cancel(); tutorTask = nil; tutorBusy = false
        resetAll()
        tutor = nil; tutorAttempt = nil; tutorBeforeAttempt = nil; tutorAI = ""; tutorContext = ""
        if let full = tutorFullReference {
            sourceReference = full; reference = full
            chords = ChordGrouping.group(full.notes, window: rubric.chordWindowMs / 1000)
        }
        tutorFullReference = nil
        if let saved = tutorSavedSetup {
            setModeNow(saved.mode); tempoPercent = saved.tempoPercent; metronomeOn = saved.metronomeOn
        }
        tutorSavedSetup = nil; setupPlayAlong(); resetTake()
    }
    func startTutorExercise() {
        guard let e = tutor?.exercise, let full = tutorFullReference else { return }
        tutorGeneration = UUID(); tutorTask?.cancel(); tutorBusy = false; tutorAI = ""
        resetAll(); tutorBeforeAttempt = tutor; tutorAttempt = e
        let sliced = full.measures(e.measures)
        sourceReference = sliced; reference = sliced
        chords = ChordGrouping.group(sliced.notes, window: rubric.chordWindowMs / 1000)
        setModeNow(e.kind == .notes ? .wait : .playAlong)
        tempoPercent = e.tempoPercent; metronomeOn = true
        setupPlayAlong(); resetTake()
        if e.kind != .notes { startTimedRun() }
    }
    func retryTutorExercise() {
        if let previous = tutorBeforeAttempt { tutor = previous }
        startTutorExercise()
    }
    func tutorGraded() {
        guard var engine = tutor, let report, let attempt = tutorAttempt else { return }
        var mapped = report
        for i in mapped.flags.indices {
            let original = attempt.originalMeasure(mapped.flags[i].position.measure)
            mapped.flags[i].position.measure = passage?.printedMeasure(forPlayed: original) ?? original
        }
        for i in mapped.results.indices {
            let original = attempt.originalMeasure(mapped.results[i].position.measure)
            mapped.results[i].position.measure = passage?.printedMeasure(forPlayed: original) ?? original
        }
        mistakeMeasures = Set(mapped.flags.map(\.position.measure))
        var evidence = report
        if attempt.kind == .assessment && (tempoPercent < 99.5 || mode != .playAlong) { evidence.passed = false }
        engine.record(evidence, replays: replaysThisTake, completedNotes: passageComplete)
        tutor = engine
        let printed = engine.exercise.measures.map { passage?.printedMeasure(forPlayed: $0) ?? $0 }
        tutorText = TutorCoaching.message(report: mapped, next: engine.exercise, mastered: engine.mastered,
                                         printedMeasures: printed, notesCompleted: attempt.kind == .notes && passageComplete)
        tutorRecent = Array((tutorRecent + [tutorText]).suffix(3))
        tutorContext = "Piece: \(score?.title ?? passage?.title ?? "Piano piece"). Teacher: \(engine.persona.name). Last exercise: \(attempt.title), bars \(attempt.measures), speed \(attempt.tempoPercent)%. Findings: \(tutorText) Selected next exercise: \(engine.exercise.title), bars \(engine.exercise.measures), speed \(engine.exercise.tempoPercent)%. Recent results: \(tutorRecent.joined(separator: "\n"))"
        var feedbackEvidence = mapped
        feedbackEvidence.flags = Array(mapped.flags.prefix(8))
        feedbackEvidence.results = Array(mapped.results.filter { $0.kind != .correct }.prefix(8))
        let measurements = (try? JSONEncoder().encode(feedbackEvidence)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        tutorContext += " Deterministic grading evidence (measurements for interpretation, not for reciting): " + measurements
        askTutor("Tell me how that attempt went, like my piano teacher, and guide me into the selected exercise.")
    }
    func askTutor(_ question: String) {
        tutorTask?.cancel(); tutorGeneration = UUID(); tutorAI = ""; tutorBusy = false
        let generation = tutorGeneration
        let context = tutorContext.isEmpty ? tutorText : tutorContext
        let client: any TutorFeedbackClient
        do {
            client = try tutorFeedbackClient ?? ModelTutorFeedbackClient.configured()
        } catch {
            return // Local teacher guidance remains available without a configured key.
        }
        tutorBusy = true
        tutorTask = Task { @MainActor [weak self] in
            do {
                let text = try await client.explain(context: context, question: question)
                guard let self, !Task.isCancelled, self.tutorGeneration == generation else { return }
                self.tutorAI = text; self.tutorBusy = false
            } catch {
                guard let self, self.tutorGeneration == generation else { return }
                self.tutorBusy = false; self.tutorAI = "" // Keep the local teacher guidance visible on failure.
            }
        }
    }
}

extension Rubric {
    /// Same thresholds as Rubrics/intermediate.md.
    static var intermediatePreset: Rubric {
        var r = Rubric()
        r.level = "intermediate"
        r.checks = [.notes, .rhythm, .tempo]
        r.notes.minAccuracy = 0.97
        r.notes.extraNotePenalty = 1.0
        r.rhythm.maxMeanIOIError = 0.15
        r.rhythm.flagIOIError = 0.30
        r.tempo.tolerance = 0.10
        r.tempo.maxSteadinessCV = 0.12
        r.playAlong.earlyMs = 150
        r.playAlong.lateMs = 250
        r.playAlong.micExtraLateMs = 100
        r.playAlong.keysExtraLateMs = 100
        r.playAlong.maxMissFraction = 0.2
        r.playAlong.maxMissesPerBar = 1
        r.playAlong.maxConsecutiveMisses = 2
        r.playAlong.minChordCoverage = 1.0
        return r
    }
}
#endif
