#if os(macOS)
import AppKit
import Foundation
import PianoGraderCore
import PianoLessons
import PianoPadState
import EarTrainingUI

/// Plays lesson pages in the Learn tab. Owns the page's `LessonEngine`, drives the player
/// through `PlayerControl`, turns player events into engine events, and saves progress.
/// Everything runs on the main thread.
final class LessonRunner: ObservableObject, PlayerObserver {
    enum Course: String, CaseIterable { case piano = "Piano lessons", ear = "Ear training", sight = "Sight reading", pieces = "My pieces" }
    @Published private(set) var course: Course = .piano
    @Published private(set) var earResult: EarQuizResult?
    /// Catalog data is read by path, independent of the lesson currently loaded in the player.
    var earPathProgress: [String: PageProgress] {
        guard let history else { return [:] }
        let all = history.lessonProgress()
        return Dictionary(uniqueKeysWithValues: EarLessonCourse.unit.pages.compactMap { page in
            all[.lessonPage(unit: EarLessonCourse.unit.id, page: page.id)].map { (page.id, $0) }
        })
    }

    func openEarPage(_ id: String) {
        selectCourse(.ear)
        open(id)
    }

    /// The sight-reading quiz on the shown page, if any.
    let sightReading = SightReadingSession()

    var sightPathProgress: [String: PageProgress] {
        guard let history else { return [:] }
        let all = history.lessonProgress()
        return Dictionary(uniqueKeysWithValues: SightReadingCourse.unit.pages.compactMap { page in
            all[.lessonPage(unit: SightReadingCourse.unitID, page: page.id)].map { (page.id, $0) }
        })
    }

    func openSightPage(_ id: String) {
        selectCourse(.sight)
        open(id)
    }

    func finishSightExercise() {
        guard case .sightReading(let b) = shownBlock, let result = sightReading.result,
              result.accuracy >= b.passAccuracy else { return }
        send(.graded(BlockResult(passed: true)))
    }

    private func startSightExercise(_ config: Block.SightReading) {
        sightReading.start(config)
        sightReading.onAnswered = { [weak self] correct in
            guard let self, self.shownBlock?.kind == .sightReading else { return }
            self.feedback = nil
            self.noteActivity()
            self.react(correct ? .cheer : .oops)
            self.saveSession()
        }
        sightReading.onFinished = { [weak self] result in
            guard let self, self.shownBlock?.kind == .sightReading else { return }
            Usage.event("SightReading.quizFinished", ["stage": result.stage.id, "correct": String(result.correct)])
            if result.accuracy < config.passAccuracy { self.send(.graded(BlockResult(passed: false))) }
        }
    }

    /// A lesson made by Teach me this piece (PieceLessonStore), from the My pieces section.
    func openPiecePage(_ id: String) {
        selectCourse(.pieces)
        if unit?.unit.page(id) == nil { unit = nil; loadUnit() }
        open(id)
    }

    /// The learner's pieces with a lesson page, newest first, and their progress.
    var piecePages: [LessonPage] { PieceLessonStore.pages().map(\.page) }
    var piecesProgress: [String: PageProgress] {
        guard let history else { return [:] }
        let all = history.lessonProgress()
        return Dictionary(uniqueKeysWithValues: piecePages.compactMap { page in
            all[.lessonPage(unit: PieceLessonBuilder.unitID, page: page.id)].map { (page.id, $0) }
        })
    }
    func previousEarBest(for page: LessonPage) -> Int? {
        guard let config = page.blocks.compactMap({ block -> Block.EarTraining? in
            if case .earTraining(let b) = block { return b }; return nil
        }).first else { return nil }
        return MainActor.assumeIsolated { player.earTraining.session.progress.stages[config.stageID.id]?.bestCorrect }
    }
    func selectCourse(_ value: Course) {
        guard value != course else { return }
        closePage()
        course = value
        warmUp = nil
        unit = nil
        loadUnit(); refreshProgress()
    }

    func finishEarExercise() {
        guard case .earTraining(let b) = shownBlock, let earResult,
              Double(earResult.correct) / Double(max(1, earResult.total)) >= b.passAccuracy else { return }
        send(.graded(BlockResult(passed: true)))
    }

    func learnerWillChange() {
        closePage(); endSession(showSummary: false); sessionSummary = nil
    }

    private func startEarExercise(_ config: Block.EarTraining) {
        earResult = nil
        player.prepareEarLesson(true)
        MainActor.assumeIsolated {
            let session = player.earTraining.session
            session.onActivity = { [weak self] activity in
                guard let self, self.shownBlock?.kind == .earTraining else { return }
                self.noteActivity()
                if activity != .listening { self.current?.earQuestionsAnswered += 1 }
                self.saveSession()
            }
            session.onQuizCompleted = { [weak self] result, id in
                guard let self, self.shownBlock?.kind == .earTraining else { return }
                self.earResult = result
                self.noteActivity()
                if self.current?.earQuizzes.contains(where: { $0.id == id }) == false {
                    self.current?.earQuizzes.append(EarQuizSummary(id: id, level: result.stage.level,
                        stage: result.stage.stage, correct: result.correct, total: result.total))
                }
                self.saveSession()
                if Double(result.correct) / Double(max(1, result.total)) < config.passAccuracy {
                    self.send(.graded(BlockResult(passed: false)))
                }
            }
            session.startLessonQuiz(stage: config.stageID, questions: config.questions, notes: config.notes)
        }
    }
    /// One line about what just happened, shown above the keyboard.
    struct Feedback: Equatable {
        enum Kind { case success, mistake, hint }
        var kind: Kind
        var text: String
        /// Stars for a starred block's run.
        var stars: Int?
    }

    // MARK: Published state

    @Published private(set) var unit: LoadedUnit?
    @Published private(set) var loadError: String?
    /// The open page; nil shows the unit's page list.
    @Published private(set) var page: LessonPage?
    /// The block on screen. Lags the engine by a moment after a pass, so the success shows first.
    @Published private(set) var shownIndex = 0
    @Published private(set) var hint: HintLevel = .none
    @Published private(set) var feedback: Feedback?
    /// The dancers' latest reaction (child pages); the view plays it out by the clock.
    @Published private(set) var dancerReaction: GremlinReaction?
    /// The finished page's result; shown instead of the page until "Back to unit" or "Play again".
    @Published private(set) var result: PageResult?
    /// Saved progress per page ID, for the page list.
    @Published private(set) var progress: [String: PageProgress] = [:]
    /// A song page's stages this visit.
    @Published private(set) var song = SongProgress()
    /// The last Perform run, shown as the results screen until Try again or Continue.
    @Published private(set) var songResult: SongResult?
    /// The teacher, from the learner's settings: rules, drill and wording.
    @Published private(set) var persona: Persona = .alex
    /// Fix my mistakes: the bar drill under way on a song page.
    @Published private(set) var drill: BarDrill?
    /// What went wrong in the last Perform run, in words.
    @Published private(set) var explanations: [String] = []
    /// The bar the results card offers to drill (enough Perform runs failed).
    @Published private(set) var drillOffer: Int?
    /// Perform runs that missed the stars needed, this visit.
    @Published private(set) var failedPerformCount = 0
    /// Song pages hide the on-screen keyboard; it comes up when mistakes pile up.
    @Published private(set) var keyboardRevealed = false
    /// The learner asked for the keyboard (the Keys button): it stays until they hide it.
    @Published var keyboardPinned = false
    /// The session that just ended, shown as the summary sheet until dismissed.
    @Published var sessionSummary: SessionSummary?
    /// Coming back: the warm-up offered, running, or its result.
    @Published private(set) var warmUp: WarmUp?
    /// A listen block played through: its Continue counts down instead of moving on at once,
    /// so there's a moment to press Listen again.
    @Published private(set) var listenDone = false
    /// A song stage just finished well: the next stage's button counts down to it.
    @Published private(set) var autoNextStage: SongStage?
    /// The teacher opens the drill herself (Kriti): the Fix bar button counts down to it.
    @Published private(set) var drillAutoStart = false

    /// What the summary sheet shows.
    struct SessionSummary: Identifiable, Equatable {
        var session: PracticeSession
        var nextPage: LessonPage?
        var streakDays: Int
        var id: UUID { session.id }
    }

    /// The return warm-up: the last timed block from a previous session, about a minute.
    struct WarmUp: Equatable {
        enum Phase: Equatable {
            case offered
            case running
            /// The warm-up's note score, 0–1.
            case done(notes: Double)
        }
        var block: TimedBlockResult
        var pageTitle: String
        var phase: Phase

        /// The score fell well short of last time's: suggest reviewing the page first.
        var suggestsReview: Bool {
            guard case .done(let notes) = phase else { return false }
            return Coach.warmUpSuggestsReview(previous: block.notes, now: notes)
        }
    }

    // MARK: Private state

    private unowned let player: PlaySession
    private var engine: LessonEngine?
    /// Mic only: a find-it note heard once, waiting to be heard again (a stray sound can't skip).
    private var micCandidate: (pitch: Int, at: TimeInterval)?
    private var pendingWork: DispatchWorkItem?
    /// Reopening a page as the app opens: a listen step waits for its button instead of playing.
    private var resumingQuietly = false
    /// The learner whose first lesson note has been recorded (metrics.json) this run.
    private var firstNoteCheckedFor: UUID?
    /// How long a success shows before the next block.
    private static let successPause = 1.0
    /// The session under way (from the first activity in the Learn tab), and whose it is.
    private var current: PracticeSession?
    private var sessionLearner: UUID?
    private var notesThisSession = 0
    private var lastActivity = Date()
    private var idleTimer: Timer?
    /// No activity for this long ends the session (with its summary).
    static let idleLimit: TimeInterval = 20 * 60
    /// A warm-up is offered when the last session ended at least this long ago.
    static let returnAfter: TimeInterval = 30 * 60
    /// Mistakes in a row, and right notes in a row since the keyboard came up.
    private var mistakesInARow = 0
    private var rightSinceReveal = 0
    /// Mistakes in a row that bring the keyboard up, and right notes in a row that put it away.
    static let revealAfterMistakes = 3
    static let hideAfterRightNotes = 4
    /// Failed Perform runs since the last drill, for choosing the bar.
    private var failedPerforms: [GradeReport] = []
    /// Bars in the whole song (the drill's context step stays inside it).
    private var songMeasureCount = 0

    init(player: PlaySession) {
        self.player = player
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.endSession(showSummary: false)
        }
    }

    // MARK: Reading

    var shownBlock: Block? {
        guard let page, page.blocks.indices.contains(shownIndex), result == nil else { return nil }
        return page.blocks[shownIndex]
    }

    var blockCount: Int { page?.blocks.count ?? 0 }

    /// Keys to pulse: an explain block's highlight, or a concept check's note.
    var highlight: Set<Int> {
        switch shownBlock {
        case .explain(let b): return Set(b.highlight.map(\.pitch))
        default: return []
        }
    }

    /// What the hint line says at the current hint level: the block's or page's own hint,
    /// then the teacher stepping in.
    var hintText: String? {
        switch hint {
        case .none:
            return nil
        case .hint:
            return page?.hint(forBlock: shownIndex) ?? "The next key to play is marked on the keyboard."
        case .teacher:
            switch shownBlock {
            case .earTraining:
                return "Replay the reference, then compare it with the example. You can listen as often as you need."
            case .sightReading:
                return "Open the examples and compare. Count the lines and spaces up from a landmark note you know."
            case .timed, .songChallenge:
                return "No rush. Press Listen to hear it again, then play along, counting the clicks."
            default:
                return "No rush. Press Listen to hear it, then play one note at a time."
            }
        }
    }

    /// Completed page IDs, for unlocking.
    var completedPages: Set<String> {
        Set(progress.filter { $0.value.isCompleted }.map(\.key))
    }

    /// Development: every page opens, in any order. Set false to lock pages until the one
    /// before is finished (the unit's `unlocks` chain) before release. The coach still suggests
    /// pages in the unit's order either way.
    static let unlockAllPages = true

    func isUnlocked(_ pageID: String) -> Bool {
        guard let unit else { return false }
        if Self.unlockAllPages || course == .pieces { return unit.unit.page(pageID) != nil }
        return unit.unit.isUnlocked(pageID, completed: completedPages)
    }

    /// The page to suggest, from the coach: an unfinished page (fewest stars first), else the
    /// next unlocked page, else the starred page with the fewest stars.
    var nextPageID: String? {
        guard let unit else { return nil }
        return Coach.nextPage(in: unit.unit, states: coachStates)?.id
    }

    private var coachStates: [String: CoachPageState] {
        progress.mapValues { p in
            CoachPageState(completed: p.isCompleted, inProgress: p.currentBlock > 0, bestStars: p.bestStars,
                           flagged: !p.flaggedBlocks.isEmpty)
        }
    }

    /// Days practised this week, for the unit page.
    var streakDays: Int {
        guard let history else { return 0 }
        var all = history.sessions()
        if let current, notesThisSession > 0 { all.append(current) }
        return WeeklyStreak.daysThisWeek(all)
    }

    /// The page hides the keyboard until it's needed: songs (not while listening, which lights
    /// the keys). Whoever plays by clicking the on-screen keys uses Show keys.
    var autoHidesKeyboard: Bool {
        guard case .songChallenge = shownBlock, songResult == nil else { return false }
        return drill != nil || song.current != .listen
    }

    var showsKeyboard: Bool { shownBlock?.kind != .earTraining && (!autoHidesKeyboard || keyboardPinned || keyboardRevealed) }

    // MARK: Child

    /// The learner is a child: stickers instead of percentages, bigger explain cards, the
    /// teacher choice with the grown-ups.
    var isChild: Bool { player.learner?.kind == .child }

    /// The Pebbles dance under the keyboard on every lesson page, for adults and children,
    /// unless the learner (or a grown-up, for a child) turned them off.
    var showsDancers: Bool { player.showsDancers }

    /// Turns the dancers on or off for this learner (the teacher menu, or For grown-ups).
    func setDancers(_ on: Bool) {
        objectWillChange.send()
        player.setDancers(on)
    }

    /// The dancers' reaction to the latest note: a hop for a right one, a wobble for a slip.
    private func react(_ kind: GremlinReaction.Kind) {
        guard showsDancers else { return }
        dancerReaction = GremlinReaction(kind: kind, startedAt: ProcessInfo.processInfo.systemUptime)
    }

    /// The sticker a page gives (the crown for the goal song).
    func sticker(forPage id: String) -> Sticker? {
        guard let pages = unit?.unit.pages, let i = pages.firstIndex(where: { $0.id == id }) else { return nil }
        return pages[i].isGoalSongPage ? Stickers.goalSong : Stickers.forPage(at: i)
    }

    /// What the "For grown-ups" panel shows.
    struct GrownUpsReport {
        var name: String
        var minutesThisWeek: Int
        var daysThisWeek: Int
        var earQuizzesThisWeek: Int
        /// New notes from finished pages, in unit order ("C", "D", "E").
        var notesLearned: [String]
        var pagesDone: Int
        var pageCount: Int
        /// The page they're stuck on (unfinished, or finished with steps skipped), and how.
        var stuckPage: LessonPage?
        var stuckDetail: String?
        var tip: String
    }

    func grownUpsReport() -> GrownUpsReport {
        refreshProgress()
        let name = player.learner?.name ?? "Your child"
        var sessions = history?.sessions() ?? []
        if let current, notesThisSession > 0 { sessions.append(current) }
        let minutes = WeeklyStreak.minutesThisWeek(sessions)
        let days = WeeklyStreak.daysThisWeek(sessions)
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        let earQuizzes = sessions.filter { week?.contains($0.started) == true }.flatMap(\.earQuizzes).count
        let pages = unit?.unit.pages ?? []
        let done = pages.filter { progress[$0.id]?.isCompleted == true }
        var notes: [String] = []
        for p in done { for n in p.newNotes where !notes.contains(n.letter) { notes.append(n.letter) } }
        var stuck: LessonPage?
        var detail: String?
        if let unit, let pick = Coach.nextPage(in: unit.unit, states: coachStates), let p = progress[pick.id] {
            if !p.isCompleted && p.currentBlock > 0 {
                stuck = pick
                detail = "Up to step \(p.currentBlock + 1) of \(pick.blocks.count)"
            } else if p.isCompleted && !p.flaggedBlocks.isEmpty {
                stuck = pick
                detail = "Finished, but skipped \(p.flaggedBlocks.count) step\(p.flaggedBlocks.count == 1 ? "" : "s")"
            }
        }
        let tip = GrownUpsTip.tip(.init(name: name, minutesThisWeek: minutes, daysThisWeek: days, stuckPage: stuck?.title,
                                        usesComputerKeyboard: player.chosenInput == .computerKeyboard,
                                        goalSong: goalSong?.title))
        return GrownUpsReport(name: name, minutesThisWeek: minutes, daysThisWeek: days, earQuizzesThisWeek: earQuizzes, notesLearned: notes,
                              pagesDone: done.count, pageCount: pages.count, stuckPage: stuck, stuckDetail: detail, tip: tip)
    }

    /// A session has started (something was played) and not ended.
    var hasSessionUnderway: Bool { current != nil && notesThisSession > 0 }

    /// The warm-up page is running.
    var isWarmingUp: Bool { warmUp?.phase == .running }

    /// Where Continue goes: the page to do next, and the step reached on it (0: not started).
    var continueTarget: (page: LessonPage, step: Int)? {
        guard let unit, let id = nextPageID, let page = unit.unit.page(id) else { return nil }
        return (page, min(progress[id]?.currentBlock ?? 0, max(0, page.blocks.count - 1)))
    }

    /// The learner's goal song from setup (Mary Had a Little Lamb when none was chosen).
    var goalSong: GoalSong? {
        GoalSongs.song(player.learnerSettings.goalSong) ?? GoalSongs.song(GoalSongs.defaultID)
    }

    /// A song challenge's title: the learner's goal song on the goal page.
    func songTitle(_ b: Block.SongChallenge) -> String {
        b.useGoalSong ? (goalSong?.title ?? b.title) : b.title
    }

    /// Finger numbers to draw over a block's notes, for each hand: its own, or for a song in
    /// C position one per note worked out from the pitch (right hand C 1 … G 5 from Middle C,
    /// left hand C 5 … G 1 an octave below). A hand with a note outside its position gets none.
    func fingering(for block: Block) -> (right: [Int], left: [Int]) {
        if block.rightFingering != nil || block.leftFingering != nil {
            return (block.rightFingering ?? [], block.leftFingering ?? [])
        }
        guard case .songChallenge = block, let score = player.score else { return ([], []) }
        // Same note order as the renderer: per staff, rests and tied continuations skipped.
        func fingers(staff: Int, left: Bool) -> [Int] {
            var result: [Int] = []
            for measure in score.measures {
                for event in measure.events(onStaff: staff).sorted(by: { $0.start < $1.start })
                where !event.isRest && !event.notes.allSatisfy(\.tieStop) {
                    // One per chord: the note nearest the number (lowest under, highest over).
                    guard let pitch = left ? event.notes.first?.midi : event.notes.last?.midi,
                          let finger = left ? MistakeExplainer.leftCFinger(pitch) : MistakeExplainer.middleCFinger(pitch)
                    else { return [] } // outside C position
                    result.append(finger)
                }
            }
            return result
        }
        let bottom = score.staves.count - 1
        let rightStaff: Int? = score.staves.count > 1 || score.staves.first == .treble ? 0 : nil
        let leftStaff: Int? = score.staves.count > 1 || score.staves.first == .bass ? bottom : nil
        return (rightStaff.map { fingers(staff: $0, left: false) } ?? [],
                leftStaff.map { fingers(staff: $0, left: true) } ?? [])
    }

    /// A song challenge's file: the learner's goal song when the block asks for it (and it's there).
    private func songPath(_ b: Block.SongChallenge) -> String {
        guard b.useGoalSong, let unit, let id = goalSong?.id else { return b.midi }
        let path = Block.SongChallenge.goalSongPath(id)
        return FileManager.default.fileExists(atPath: unit.url(for: path).path) ? path : b.midi
    }

    /// What a page on the map plays when previewed: its song or fullest exercise, at the
    /// tempo the lesson plays it. Nil when it has nothing to hear.
    func preview(of page: LessonPage) -> (url: URL, tempo: Double?)? {
        guard let unit, let block = page.previewBlock else { return nil }
        switch block {
        case .songChallenge(let b): return (unit.url(for: songPath(b)), nil)
        case .listen(let b): return (unit.url(for: b.midi), b.tempo)
        case .timed(let b): return (unit.url(for: b.midi), b.tempo)
        default: return block.midi.map { (unit.url(for: $0), nil) }
        }
    }

    /// The same for a page in My pieces, whichever course is showing: the whole piece.
    func preview(ofPiecePage page: LessonPage) -> (url: URL, tempo: Double?)? {
        guard let midi = page.previewBlock?.midi else { return nil }
        let key = page.id.hasPrefix("piece-") ? String(page.id.dropFirst("piece-".count)) : page.id
        return (PieceLessonStore.folder(key).appendingPathComponent(midi), nil)
    }

    /// Stars earned across the unit's pages, and the most there are.
    var unitStars: (earned: Int, possible: Int) {
        guard let unit else { return (0, 0) }
        let starred = unit.unit.pages.filter { !$0.starredBlocks.isEmpty }
        return (starred.reduce(0) { $0 + (progress[$1.id]?.bestStars ?? 0) }, starred.count * 3)
    }

    // MARK: Tab

    /// The Learn tab opened.
    func arrive() {
        if page == nil && course != .piano { selectCourse(.piano) }
        if unit == nil { loadUnit() }
        loadPersona()
        refreshProgress()
        offerWarmUpIfReturning()
    }

    /// The Learn tab closed: end any lesson and give the practice piece back, and end the
    /// session with its summary.
    func leave() {
        if isWarmingUp { warmUp = nil }
        closePage()
        player.rememberLessonPage(nil)
        endSession(showSummary: true)
    }

    // MARK: Pages

    func open(_ pageID: String) {
        open(pageID, atBlock: nil)
    }

    /// Back to the page the learner left off on, at its saved step. Nothing plays by itself.
    func resume(_ pageID: String) {
        arrive()
        resumingQuietly = true
        defer { resumingQuietly = false }
        if EarLessonCourse.unit.page(pageID) != nil {
            openEarPage(pageID)
        } else if SightReadingCourse.unit.page(pageID) != nil {
            openSightPage(pageID)
        } else if pageID.hasPrefix("piece-") {
            openPiecePage(pageID)
        } else {
            open(pageID)
        }
    }

    /// `atBlock`: start there (the warm-up) instead of the saved position.
    private func open(_ pageID: String, atBlock: Int?) {
        guard let unit, let page = unit.unit.page(pageID), isUnlocked(pageID) else { return }
        closePage()
        // Going straight to a page: no warm-up this time (or its result has been seen).
        if atBlock == nil, let w = warmUp, w.phase != .running { warmUp = nil }
        touchSession(page: pageID)
        let resume = atBlock ?? history?.lessonProgress(unit: unit.unit.id, page: pageID)?.currentBlock ?? 0
        loadPersona()
        engine = LessonEngine(page: page, rules: persona.rules, startAt: resume)
        self.page = page
        // A warm-up is a detour, not a place to come back to.
        player.rememberLessonPage(atBlock == nil ? pageID : nil)
        Usage.event("Lesson.pageOpened", ["page": pageID, "step": String(resume + 1), "warmUp": atBlock != nil ? "yes" : "no"])
        player.beginLesson(piece: .lessonPage(unit: unit.unit.id, page: pageID), observer: self)
        enterBlock()
    }

    /// Back to the page list. The block reached is saved, so the page resumes there.
    func backToUnit() {
        if isWarmingUp { warmUp = nil }
        closePage()
        player.rememberLessonPage(nil)
        if course != .piano { selectCourse(.piano) }
        refreshProgress()
    }

    /// From the finished screen: the page to go on to (the coach's pick), when it's another page.
    var nextPageAfterDone: LessonPage? {
        guard result != nil, let unit, let id = nextPageID, id != page?.id, isUnlocked(id) else { return nil }
        return unit.unit.page(id)
    }

    /// From the finished screen: on to the next page.
    func openNextPage() {
        guard let next = nextPageAfterDone else { return }
        open(next.id)
    }

    /// From the finished screen: the same page again from the top.
    func playAgain() {
        guard let id = page?.id else { return }
        open(id)
    }

    // MARK: Controls

    func continueTapped() { send(.continueTapped) }

    func skip() {
        guard !isWarmingUp else {
            backToUnit()
            return
        }
        Usage.event("Lesson.stepSkipped", stepParameters)
        send(.skip)
    }

    /// Back to the previous step (the page's position is saved there).
    func back() {
        guard canGoBack else { return }
        Usage.event("Lesson.stepBack", stepParameters)
        pendingWork?.cancel()
        pendingWork = nil
        player.stopPlayAlong(discard: true)
        if player.isAuditioning { player.stopListening() }
        send(.back)
    }

    /// The page and step, for usage events.
    private var stepParameters: [String: String] {
        ["page": page?.id ?? "", "step": String(shownIndex + 1), "stepKind": shownBlock?.kind.rawValue ?? ""]
    }

    /// Back is offered from the second step on, but not in the one-step warm-up.
    var canGoBack: Bool { page != nil && result == nil && shownIndex > 0 && !isWarmingUp }

    /// Starts the current block over (attempts so far still count toward hints).
    func restart() {
        feedback = nil
        autoNextStage = nil
        reloadBlock()
        send(.restart)
    }

    // MARK: Song stages

    /// Opens a song stage (any of them; the order is only a suggestion).
    func goToStage(_ stage: SongStage) {
        guard case .songChallenge = shownBlock else { return }
        pendingWork?.cancel()
        pendingWork = nil
        drill = nil
        songResult = nil
        feedback = nil
        autoNextStage = nil
        drillAutoStart = false
        song.go(to: stage)
        reloadBlock()
    }

    /// From the results screen: Perform again.
    func performAgain() { goToStage(.perform) }

    /// From the results screen: the Perform run's stars count and the page moves on.
    func continueFromSong() {
        guard let r = songResult, r.passed else { return }
        songResult = nil
        send(.graded(BlockResult(passed: true, stars: r.stars)))
    }

    /// From the results screen, after failed runs: move on without the stars (flagged, like a skip).
    func moveOnFromSong() {
        songResult = nil
        send(.askToMoveOn)
    }

    /// The results card offers "Move on anyway" once the drill would be offered.
    var canMoveOnFromSong: Bool {
        guard let r = songResult, !r.passed else { return false }
        return failedPerformCount >= persona.drill.afterFailedPerforms
    }

    // MARK: Teacher

    /// Switches the learner's teacher (saved in their settings).
    func setPersona(_ id: String) {
        player.learnerSettings.persona = id
        player.saveLearnerSettings()
        loadPersona()
        engine?.rules = persona.rules
    }

    private func loadPersona() {
        let p = Persona.load(player.learnerSettings.persona, folder: PlaySession.bundledResource("Lessons/personas"))
        if p != persona { persona = p }
    }

    // MARK: Fix my mistakes

    /// Opens the drill on the offered bar.
    func startDrill() {
        guard let bar = drillOffer, case .songChallenge = shownBlock else { return }
        pendingWork?.cancel()
        pendingWork = nil
        player.stopPlayAlong(discard: true)
        drill = RemediationPlanner.drill(measure: bar, measureCount: songMeasureCount, persona: persona)
        Usage.event("Lesson.drillStarted", ["page": page?.id ?? "", "teacher": persona.id])
        songResult = nil
        drillOffer = nil
        drillAutoStart = false
        autoNextStage = nil
        failedPerforms = []
        feedback = Feedback(kind: .hint, text: persona.say(.drillIntro, bar: bar))
        reloadBlock()
    }

    /// The learner asks to move on from the current drill step.
    func drillMoveOn() {
        guard var d = drill else { return }
        pendingWork?.cancel()
        pendingWork = nil
        player.stopPlayAlong(discard: true)
        let outcome = d.moveOn()
        drill = d
        handleDrill(outcome)
    }

    /// Leaves the drill for the song's Perform stage.
    func leaveDrill() {
        goToStage(.perform)
    }

    private func drillGraded(_ report: GradeReport) {
        guard var d = drill, let step = d.step else { return }
        // Wait mode only finishes once every note was played: that's the step done.
        let clean = step.isWaitMode || RemediationPlanner.isClean(report, replays: player.replaysThisTake)
        let outcome = d.record(clean: clean)
        drill = d
        handleDrill(outcome)
    }

    private func handleDrill(_ outcome: BarDrill.Outcome) {
        guard let d = drill else { return }
        switch outcome {
        case .again(let clean):
            feedback = Feedback(kind: clean ? .success : .mistake, text: persona.say(clean ? .runClean : .runAgain))
            // Loop: the same bar again after a moment.
            after(1.2) { [weak self] in
                guard let self, let step = self.drill?.step else { return }
                if step.isWaitMode { self.reloadBlock() } else { self.player.startTimedRun() }
            }
        case .nextStep(let step, let movedOn):
            feedback = Feedback(kind: movedOn ? .hint : .success,
                                text: persona.say(movedOn ? .movingOn : .stepDone, step: step.title))
            after(Self.successPause) { [weak self] in self?.reloadBlock() }
        case .finished:
            let bar = d.measure
            drill = nil
            song.finish(.practise) // drilling is practice: the next Perform used help
            after(Self.successPause) { [weak self] in
                guard let self else { return }
                self.song.go(to: .perform)
                self.reloadBlock()
                self.feedback = Feedback(kind: .success, text: self.persona.say(.drillDone, bar: bar))
            }
        }
    }

    /// Practise runs at the block's slowest practice tempo.
    private func practiceTempo(_ b: Block.SongChallenge) -> Double {
        (b.practiceTempos.first ?? 0.7) * 100
    }

    private func songStageGraded(_ report: GradeReport, rubric: Rubric, helpUsed: Bool) {
        let stage = song.current
        switch stage {
        case .listen:
            break
        case .learn:
            song.finish(.learn)
            autoNextStage = .practise
            feedback = Feedback(kind: .success, text: "You've learned it. Next: Practise with the clicks.")
        case .practise:
            let s = Stars.summary(report: report, rubric: rubric, helpUsed: true)
            let timing = s.timing.map { " · timing \(Int(($0 * 100).rounded()))%" } ?? ""
            song.finish(.practise)
            // On to Perform by itself only when the practice run went well enough for a star.
            autoNextStage = Stars.compute(s) >= 1 ? .perform : nil
            feedback = Feedback(kind: .success,
                                text: isChild ? "Good practice! Next: play it all the way through."
                                    : "Practice run: notes \(Int((s.notes * 100).rounded()))%\(timing). Next: Perform at full speed.")
        case .perform:
            let s = Stars.summary(report: report, rubric: rubric, helpUsed: helpUsed || song.usedHelp)
            song.finish(.perform)
            feedback = nil
            let result = SongResult(stars: Stars.compute(s), summary: s, requiredStars: engine?.rules.requiredStars ?? 1)
            explanations = MistakeExplainer.explain(report, finger: MistakeExplainer.cPositionFinger,
                                                    isLeftHand: { $0 < 60 })
            drillOffer = nil
            if result.passed {
                failedPerforms = []
            } else {
                failedPerformCount += 1
                failedPerforms = Array((failedPerforms + [report]).suffix(max(1, persona.drill.afterFailedPerforms)))
                if failedPerforms.count >= persona.drill.afterFailedPerforms {
                    drillOffer = RemediationPlanner.worstMeasure(in: failedPerforms)
                    if drillOffer != nil && persona.drill.startsAutomatically {
                        // This teacher starts the drill herself, once the results have been
                        // seen: the Fix bar button counts down (hovering pauses it).
                        drillAutoStart = true
                    }
                }
            }
            songResult = result
            Usage.event("Lesson.performed", ["page": page?.id ?? "", "passed": result.passed ? "yes" : "no",
                                             "teacher": persona.id], value: Double(result.stars))
        }
    }

    func listen() {
        if player.isAuditioning {
            player.stopListening()
        } else {
            // Listening again: no counting down to the next thing meanwhile.
            listenDone = false
            autoNextStage = nil
            player.startListening()
        }
    }

    /// Timed blocks: start the count-in, or stop.
    func startOrStop() {
        if player.isPlayingAlong {
            player.stopPlayAlong(discard: true)
        } else {
            feedback = nil
            player.startTimedRun()
        }
    }

    // MARK: PlayerObserver

    func playerNotePlayed(_ pitch: Int, source: InputSource) {
        recordFirstNoteIfNeeded()
        noteActivity()
        let target: Int?
        switch shownBlock {
        case .explain(let b): target = b.advanceOn?.pitch
        case .concept(let b): target = b.check?.pitch
        case .sightReading:
            sightNotePlayed(pitch, source: source)
            return
        default: return
        }
        guard let target, pendingWork == nil else { return }
        guard pitch == target else {
            micCandidate = nil
            feedback = Feedback(kind: .mistake, text: "That's \(NoteName(pitch: pitch).name). Try again.")
            react(.oops)
            return
        }
        if source == .microphone {
            // The mic must hear it twice in a row (within 3 s) before it counts.
            let now = ProcessInfo.processInfo.systemUptime
            guard let first = micCandidate, first.pitch == pitch, now - first.at < 3 else {
                micCandidate = (pitch, now)
                feedback = Feedback(kind: .hint, text: "Heard \(NoteName(pitch: pitch).name). Play it once more.")
                return
            }
            micCandidate = nil
        }
        feedback = Feedback(kind: .success, text: "That's it: \(NoteName(pitch: pitch).name).")
        react(.cheer)
        send(.notePlayed(pitch: pitch), pause: true)
    }

    /// A key played during a reading quiz answers a note-name question. The mic must hear it
    /// twice in a row, as for find-it notes.
    private func sightNotePlayed(_ pitch: Int, source: InputSource) {
        guard sightReading.canAnswer, let question = sightReading.question else { return }
        guard question.playPitch != nil else {
            // Lines and spaces, clefs: no key is the answer. Say so rather than stay silent.
            if source != .microphone {
                feedback = Feedback(kind: .hint, text: "That's \(NoteName(pitch: pitch).name). This question is answered with the buttons above.")
            }
            return
        }
        if source == .microphone {
            let now = ProcessInfo.processInfo.systemUptime
            guard let first = micCandidate, first.pitch == pitch, now - first.at < 3 else {
                micCandidate = (pitch, now)
                feedback = Feedback(kind: .hint, text: "Heard \(NoteName(pitch: pitch).name). Play it once more.")
                return
            }
            micCandidate = nil
        }
        feedback = nil
        sightReading.play(pitch)
    }

    func playerWrongNote(onChord chord: Int) {
        keyboardMistake()
        react(.oops)
        send(.wrongNote(chord: chord))
    }

    func playerChordPlayed(_ chord: Int) {
        keyboardRight()
        react(.cheer)
        send(.chordPlayed(chord: chord))
    }

    func playerPlayAlongNote(matched: Bool) {
        matched ? keyboardRight() : keyboardMistake()
        // Right notes in time are what the dance itself celebrates; only a slip shows.
        if !matched { react(.oops) }
    }

    func playerBarReplayed() {
        revealKeyboard()
    }

    // MARK: Keyboard on song pages

    private func keyboardMistake() {
        rightSinceReveal = 0
        mistakesInARow += 1
        if mistakesInARow >= Self.revealAfterMistakes { revealKeyboard() }
    }

    private func keyboardRight() {
        mistakesInARow = 0
        guard keyboardRevealed else { return }
        rightSinceReveal += 1
        if rightSinceReveal >= Self.hideAfterRightNotes {
            rightSinceReveal = 0
            keyboardRevealed = false
        }
    }

    private func revealKeyboard() {
        rightSinceReveal = 0
        guard autoHidesKeyboard, !keyboardRevealed else { return }
        keyboardRevealed = true
    }

    /// A new block or stage starts with the keyboard put away again.
    private func resetKeyboard() {
        mistakesInARow = 0
        rightSinceReveal = 0
        keyboardRevealed = false
    }

    func playerListenFinished() {
        switch shownBlock {
        case .listen:
            // Continue counts down now (it used to move on at once); the engine moves on
            // when it's pressed, by the learner or the countdown.
            listenDone = true
        case .songChallenge where song.current == .listen && drill == nil:
            song.finish(.listen)
            autoNextStage = .learn
            feedback = Feedback(kind: .success, text: "That's the song. Next: Learn it at your own pace.")
        default:
            break
        }
    }

    func playerGraded(_ report: GradeReport, rubric: Rubric, helpUsed: Bool) {
        guard let block = shownBlock, block.isGraded, pendingWork == nil else { return }
        if case .songChallenge = block {
            if drill != nil {
                drillGraded(report)
            } else {
                songStageGraded(report, rubric: rubric, helpUsed: helpUsed)
            }
            return
        }
        if block.awardsStars {
            let summary = Stars.summary(report: report, rubric: rubric, helpUsed: helpUsed)
            let stars = Stars.compute(summary)
            if case .timed = block, let unit, let page {
                let result = TimedBlockResult(unit: unit.unit.id, page: page.id, block: shownIndex, notes: summary.notes)
                current?.lastTimed = result
                saveSession()
                if isWarmingUp {
                    finishWarmUp(notes: summary.notes)
                    return
                }
            }
            let timing = summary.timing.map { " · timing \(Int(($0 * 100).rounded()))%" } ?? ""
            let line = "Notes \(Int((summary.notes * 100).rounded()))%\(timing)"
            let text = isChild ? Stickers.cheer(stars: stars) : (stars > 0 ? "\(line). Well played!" : "\(line). Not quite yet.")
            feedback = Feedback(kind: stars > 0 ? .success : .mistake, text: text, stars: stars)
            send(.graded(BlockResult(passed: true, stars: stars)), pause: true)
        } else {
            // Wait mode only finishes once every note was played, so a graded take has passed.
            feedback = Feedback(kind: .success, text: "Well done.")
            send(.graded(BlockResult(passed: true)), pause: true)
        }
    }

    // MARK: Sessions

    /// "Finish for today" on the unit page: end the session and show its summary.
    func finishSession() {
        endSession(showSummary: true)
    }

    /// From the summary sheet: go on with the suggested page.
    func keepGoing(with pageID: String) {
        sessionSummary = nil
        if player.tab != .learn { player.tab = .learn }
        if EarLessonCourse.unit.page(pageID) != nil {
            openEarPage(pageID)
        } else if SightReadingCourse.unit.page(pageID) != nil {
            openSightPage(pageID)
        } else if pageID.hasPrefix("piece-") {
            openPiecePage(pageID)
        } else {
            selectCourse(.piano)
            open(pageID)
        }
    }

    /// A key was played (or a page finished): starts the session if needed and keeps it alive.
    private func noteActivity() {
        guard let learner = player.learner else { return }
        if current != nil && sessionLearner != learner.id { endSession(showSummary: false) }
        let now = Date()
        if current == nil {
            current = PracticeSession(started: now)
            sessionLearner = learner.id
            notesThisSession = 0
            startIdleTimer()
        }
        notesThisSession += 1
        lastActivity = now
        current?.ended = now
        if let id = page?.id, current?.pages.contains(id) == false { current?.pages.append(id) }
    }

    /// A page was opened: noted in the session under way.
    private func touchSession(page id: String) {
        guard var s = current, !s.pages.contains(id) else { return }
        s.pages.append(id)
        current = s
    }

    private func saveSession() {
        guard let current, notesThisSession > 0, let id = sessionLearner else { return }
        try? player.learnerStore.history(for: id).recordSession(current)
    }

    /// Saves the session (when anything was played) and, with `showSummary`, shows its summary.
    private func endSession(showSummary: Bool) {
        idleTimer?.invalidate()
        idleTimer = nil
        guard var s = current else { return }
        current = nil
        defer { sessionLearner = nil }
        guard notesThisSession > 0, let id = sessionLearner else { return }
        s.ended = max(s.started, lastActivity)
        let history = player.learnerStore.history(for: id)
        try? history.recordSession(s)
        guard showSummary, player.learner?.id == id else { return }
        refreshProgress()
        let next = nextPageID.flatMap { unit?.unit.page($0) }
        sessionSummary = SessionSummary(session: s, nextPage: next,
                                        streakDays: WeeklyStreak.daysThisWeek(history.sessions()))
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.current != nil else { return }
            if Date().timeIntervalSince(self.lastActivity) >= Self.idleLimit {
                if self.isWarmingUp { self.warmUp = nil }
                self.closePage()
                self.endSession(showSummary: true)
                if self.course != .piano { self.selectCourse(.piano) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: Warm-up

    /// Coming back after a break: offer the last timed block from a previous session.
    private func offerWarmUpIfReturning() {
        guard current == nil, page == nil, warmUp == nil, let unit, let history,
              let last = history.sessions().last, Date().timeIntervalSince(last.ended) >= Self.returnAfter,
              let timed = history.lastTimedBlock(), timed.unit == unit.unit.id,
              let warmPage = unit.unit.page(timed.page), warmPage.blocks.indices.contains(timed.block),
              case .timed = warmPage.blocks[timed.block] else { return }
        warmUp = WarmUp(block: timed, pageTitle: warmPage.title, phase: .offered)
    }

    func startWarmUp() {
        guard var w = warmUp else { return }
        w.phase = .running
        warmUp = w
        open(w.block.page, atBlock: w.block.block)
    }

    func dismissWarmUp() {
        warmUp = nil
    }

    /// From the warm-up result: review the warm-up's page first.
    func reviewWarmUpPage() {
        guard let id = warmUp?.block.page else { return }
        warmUp = nil
        open(id)
    }

    /// From the warm-up result: on to the coach's page.
    func continueAfterWarmUp() {
        warmUp = nil
        if let id = nextPageID { open(id) }
    }

    private func finishWarmUp(notes: Double) {
        guard var w = warmUp else { return }
        w.phase = .done(notes: notes)
        feedback = Feedback(kind: .success, text: isChild ? "Warmed up!" : "Warmed up: notes \(Int((notes * 100).rounded()))%.")
        after(Self.successPause) { [weak self] in
            guard let self else { return }
            self.warmUp = w
            self.closePage()
            self.refreshProgress()
        }
        // Keep `running` until the page closes, so nothing else reads the take as a lesson run.
    }

    // MARK: Private

    /// The time-to-first-note measure: the learner's first note on any lesson page.
    private func recordFirstNoteIfNeeded() {
        guard page != nil, let learner = player.learner, firstNoteCheckedFor != learner.id else { return }
        firstNoteCheckedFor = learner.id
        _ = try? player.learnerStore.history(for: learner.id).recordFirstLessonNote(appLaunched: player.launchedAt)
    }

    private var history: LearnerHistory? {
        player.learner.map { player.learnerStore.history(for: $0.id) }
    }

    var todaySessions: [PracticeSession] {
        PracticeTotals.today((history?.sessions() ?? []) + [current].compactMap { $0 })
    }

    private func loadUnit() {
        if course == .ear {
            unit = LoadedUnit(unit: EarLessonCourse.unit, folder: FileManager.default.temporaryDirectory)
            loadError = nil
            return
        }
        if course == .sight {
            unit = LoadedUnit(unit: SightReadingCourse.unit, folder: FileManager.default.temporaryDirectory)
            loadError = nil
            return
        }
        if course == .pieces {
            guard let pieces = PieceLessonStore.unit() else {
                loadError = "No piece lessons yet: open a piece in Practice and choose Teach me this piece."
                return
            }
            let errors = pieces.validate()
            unit = pieces
            loadError = errors.isEmpty ? nil : errors.map(\.description).joined(separator: "\n")
            return
        }
        guard let folder = PlaySession.bundledResource("Lessons/unit1") else {
            loadError = "Lessons/unit1 wasn't found in the app or next to it."
            return
        }
        do {
            unit = try LoadedUnit.load(folder: folder)
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    private func refreshProgress() {
        guard let unit, let history else {
            progress = [:]
            return
        }
        var all: [String: PageProgress] = [:]
        for p in unit.unit.pages {
            if let saved = history.lessonProgress(unit: unit.unit.id, page: p.id) { all[p.id] = saved }
        }
        progress = all
    }

    private func closePage() {
        player.prepareEarLesson(false)
        earResult = nil
        sightReading.stop()
        pendingWork?.cancel()
        pendingWork = nil
        if page != nil { player.endLesson() }
        engine = nil
        page = nil
        result = nil
        feedback = nil
        song = SongProgress()
        songResult = nil
        resetDrill()
        hint = .none
        micCandidate = nil
        listenDone = false
        shownIndex = 0
    }

    /// Feeds the engine and acts on what it says. With `pause`, moving on waits a moment so
    /// the success can be seen.
    private func send(_ event: LessonEvent, pause: Bool = false) {
        guard engine != nil else { return }
        let effects = engine!.handle(event)
        for effect in effects {
            switch effect {
            case .hint(let level):
                hint = level
            case .retry:
                // The run didn't reach the stars needed; the feedback line already says how it went.
                break
            case .advanced:
                after(pause ? Self.successPause : 0) { [weak self] in self?.enterBlock() }
            case .pageComplete(let r):
                record(r)
                after(pause ? Self.successPause : 0) { [weak self] in
                    guard let self else { return }
                    self.player.prepareEarLesson(false)
                    self.player.showNothing()
                    self.result = r
                }
            }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        pendingWork?.cancel()
        guard seconds > 0 else {
            pendingWork = nil
            work()
            return
        }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingWork = nil
            work()
        }
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Shows the engine's current block and gets the player ready for it.
    private func enterBlock() {
        guard let engine, !engine.isComplete else { return }
        shownIndex = engine.blockIndex
        listenDone = false
        feedback = nil
        hint = engine.hintLevel
        song = SongProgress()
        songResult = nil
        resetDrill()
        micCandidate = nil
        if !isWarmingUp { savePosition() }
        reloadBlock()
    }

    private func resetDrill() {
        resetKeyboard()
        drill = nil
        drillOffer = nil
        drillAutoStart = false
        autoNextStage = nil
        explanations = []
        failedPerforms = []
        failedPerformCount = 0
    }

    /// Loads (or reloads) the player for the shown block.
    private func reloadBlock() {
        player.prepareEarLesson(false)
        earResult = nil
        sightReading.stop()
        resetKeyboard()
        guard let unit, let page, let block = shownBlock else { return }
        let piece = PieceID.lesson(unit: unit.unit.id, page: page.id, block: shownIndex)
        func load(_ midi: String, mode: PlaySession.PracticeMode, tempo: Double?, countIn: Int = 4,
                  measures: ClosedRange<Int>? = nil) {
            player.loadLessonBlock(midi: unit.url(for: midi), piece: piece, mode: mode, tempo: tempo,
                                   countInBeats: countIn, measures: measures)
        }
        switch block {
        case .earTraining(let b):
            player.showNothing()
            startEarExercise(b)
        case .sightReading(let b):
            player.showNothing()
            startSightExercise(b)
        case .explain, .concept:
            player.showNothing()
        case .wait(let b):
            load(b.midi, mode: .wait, tempo: nil)
        case .listen(let b):
            load(b.midi, mode: .wait, tempo: b.tempo)
            if !resumingQuietly { player.startListening() }
        case .timed(let b):
            load(b.midi, mode: .playAlong, tempo: b.tempo, countIn: b.countInBeats)
            // The count-in starts by itself, so the step never sits waiting for Start.
            if !resumingQuietly { player.startTimedRun() }
        case .songChallenge(let b):
            let path = songPath(b)
            if let step = drill?.step {
                // Fix my mistakes: just the drilled bars.
                load(path, mode: step.isWaitMode ? .wait : .playAlong, tempo: nil, measures: step.measures)
                if !step.isWaitMode {
                    player.setLessonTempo(percent: step.tempoPercent)
                    player.setLessonPlayAlong(persona.playAlong)
                }
                return
            }
            defer { songMeasureCount = player.lessonMeasureCount }
            switch song.current {
            case .listen:
                load(path, mode: .wait, tempo: nil)
                if !resumingQuietly { player.startListening() }
            case .learn:
                load(path, mode: .wait, tempo: nil)
            case .practise:
                load(path, mode: .playAlong, tempo: nil)
                player.setLessonTempo(percent: practiceTempo(b))
                player.setLessonPlayAlong(persona.playAlong)
            case .perform:
                load(path, mode: .playAlong, tempo: nil)
                // No stops: one run from start to finish, graded once.
                player.setLessonPlayAlong(.keepGoing)
            }
        }
    }

    private func savePosition() {
        guard let unit, let page, let history else { return }
        try? history.saveLessonPosition(unit: unit.unit.id, page: page.id, block: shownIndex)
    }

    private func record(_ r: PageResult) {
        guard let unit, let page, let history else { return }
        let firstTime = history.lessonProgress(unit: unit.unit.id, page: page.id)?.isCompleted != true
        noteActivity()
        if var s = current {
            if !s.completedPages.contains(page.id) { s.completedPages.append(page.id) }
            if firstTime {
                for note in page.newNotes where !s.notesLearned.contains(note.letter) { s.notesLearned.append(note.letter) }
            }
            s.stars += r.stars ?? 0
            current = s
            saveSession()
        }
        Usage.event("Lesson.pageCompleted", ["page": page.id, "firstTime": firstTime ? "yes" : "no",
                                             "skippedSteps": String(r.flaggedBlocks.count)],
                    value: r.stars.map(Double.init))
        do {
            try history.recordPageComplete(unit: unit.unit.id, page: page.id, stars: r.stars, flaggedBlocks: r.flaggedBlocks)
        } catch {
            player.message = "Couldn't save lesson progress: \(error.localizedDescription)"
        }
        // Finished: next time they come back to the page list, with the next page suggested.
        player.rememberLessonPage(nil)
        refreshProgress()
    }
}
#endif
