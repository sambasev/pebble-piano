#if os(macOS)
import AppKit
import Foundation
import PianoGraderCore
import PianoLessons
import PianoPadState

/// Plays lesson pages in the Learn tab. Owns the page's `LessonEngine`, drives the player
/// through `PlayerControl`, turns player events into engine events, and saves progress.
/// Everything runs on the main thread.
final class LessonRunner: ObservableObject, PlayerObserver {
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

    func isUnlocked(_ pageID: String) -> Bool {
        unit?.unit.isUnlocked(pageID, completed: completedPages) ?? false
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

    var showsKeyboard: Bool { !autoHidesKeyboard || keyboardPinned || keyboardRevealed }

    // MARK: Child

    /// The learner is a child: stickers instead of percentages, bigger explain cards, the
    /// teacher choice with the grown-ups.
    var isChild: Bool { player.learner?.kind == .child }

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
        return GrownUpsReport(name: name, minutesThisWeek: minutes, daysThisWeek: days, notesLearned: notes,
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

    /// Finger numbers to draw over a block's notes: its own, or for a song in Middle C position
    /// one per note worked out from the pitch (C 1, D 2, E 3, F 4, G 5).
    func fingering(for block: Block) -> [Int]? {
        if let own = block.fingering { return own }
        guard case .songChallenge = block, let notes = player.reference?.notes, !notes.isEmpty else { return nil }
        let fingers: [Int: Int] = [60: 1, 62: 2, 64: 3, 65: 4, 67: 5]
        var result: [Int] = []
        var lastOnset = -Double.infinity
        for note in notes.sorted(by: { $0.onset < $1.onset }) {
            guard let finger = fingers[note.pitch] else { return nil } // outside C position
            if note.onset - lastOnset > 0.03 { result.append(finger) } // one per chord
            lastOnset = note.onset
        }
        return result
    }

    /// A song challenge's file: the learner's goal song when the block asks for it (and it's there).
    private func songPath(_ b: Block.SongChallenge) -> String {
        guard b.useGoalSong, let unit, let id = goalSong?.id else { return b.midi }
        let path = Block.SongChallenge.goalSongPath(id)
        return FileManager.default.fileExists(atPath: unit.url(for: path).path) ? path : b.midi
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
        endSession(showSummary: true)
    }

    // MARK: Pages

    func open(_ pageID: String) {
        open(pageID, atBlock: nil)
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
        player.beginLesson(piece: .lessonPage(unit: unit.unit.id, page: pageID), observer: self)
        enterBlock()
    }

    /// Back to the page list. The block reached is saved, so the page resumes there.
    func backToUnit() {
        if isWarmingUp { warmUp = nil }
        closePage()
        refreshProgress()
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
        send(.skip)
    }

    /// Starts the current block over (attempts so far still count toward hints).
    func restart() {
        feedback = nil
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
        songResult = nil
        drillOffer = nil
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
            feedback = Feedback(kind: .success, text: "You've learned it. Next: Practise with the clicks.")
        case .practise:
            let s = Stars.summary(report: report, rubric: rubric, helpUsed: true)
            let timing = s.timing.map { " · timing \(Int(($0 * 100).rounded()))%" } ?? ""
            song.finish(.practise)
            feedback = Feedback(kind: .success,
                                text: isChild ? "Good practice! Next: play it all the way through."
                                    : "Practice run: notes \(Int((s.notes * 100).rounded()))%\(timing). Next: Perform at full speed.")
        case .perform:
            let s = Stars.summary(report: report, rubric: rubric, helpUsed: helpUsed || song.usedHelp)
            song.finish(.perform)
            feedback = nil
            let result = SongResult(stars: Stars.compute(s), summary: s, requiredStars: engine?.rules.requiredStars ?? 1)
            explanations = MistakeExplainer.explain(report, finger: MistakeExplainer.middleCFinger)
            drillOffer = nil
            if result.passed {
                failedPerforms = []
            } else {
                failedPerformCount += 1
                failedPerforms = Array((failedPerforms + [report]).suffix(max(1, persona.drill.afterFailedPerforms)))
                if failedPerforms.count >= persona.drill.afterFailedPerforms {
                    drillOffer = RemediationPlanner.worstMeasure(in: failedPerforms)
                    if drillOffer != nil && persona.drill.startsAutomatically {
                        // This teacher starts the drill herself, once the results have been seen.
                        after(4) { [weak self] in self?.startDrill() }
                    }
                }
            }
            songResult = result
        }
    }

    func listen() {
        player.isAuditioning ? player.stopListening() : player.startListening()
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
        default: return
        }
        guard let target, pendingWork == nil else { return }
        guard pitch == target else {
            micCandidate = nil
            feedback = Feedback(kind: .mistake, text: "That's \(NoteName(pitch: pitch).name). Try again.")
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
        send(.notePlayed(pitch: pitch), pause: true)
    }

    func playerWrongNote(onChord chord: Int) {
        keyboardMistake()
        send(.wrongNote(chord: chord))
    }

    func playerChordPlayed(_ chord: Int) {
        keyboardRight()
        send(.chordPlayed(chord: chord))
    }

    func playerPlayAlongNote(matched: Bool) {
        matched ? keyboardRight() : keyboardMistake()
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
            send(.listenFinished)
        case .songChallenge where song.current == .listen:
            song.finish(.listen)
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
        open(pageID)
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

    private func loadUnit() {
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
        explanations = []
        failedPerforms = []
        failedPerformCount = 0
    }

    /// Loads (or reloads) the player for the shown block.
    private func reloadBlock() {
        resetKeyboard()
        guard let unit, let page, let block = shownBlock else { return }
        let piece = PieceID.lesson(unit: unit.unit.id, page: page.id, block: shownIndex)
        func load(_ midi: String, mode: PlaySession.PracticeMode, tempo: Double?, countIn: Int = 4,
                  measures: ClosedRange<Int>? = nil) {
            player.loadLessonBlock(midi: unit.url(for: midi), piece: piece, mode: mode, tempo: tempo,
                                   countInBeats: countIn, measures: measures)
        }
        switch block {
        case .explain, .concept:
            player.showNothing()
        case .wait(let b):
            load(b.midi, mode: .wait, tempo: nil)
        case .listen(let b):
            load(b.midi, mode: .wait, tempo: b.tempo)
            player.startListening()
        case .timed(let b):
            load(b.midi, mode: .playAlong, tempo: b.tempo, countIn: b.countInBeats)
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
                player.startListening()
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
        do {
            try history.recordPageComplete(unit: unit.unit.id, page: page.id, stars: r.stars, flaggedBlocks: r.flaggedBlocks)
        } catch {
            player.message = "Couldn't save lesson progress: \(error.localizedDescription)"
        }
        refreshProgress()
    }
}
#endif
