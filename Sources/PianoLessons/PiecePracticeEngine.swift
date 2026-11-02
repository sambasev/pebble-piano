import Foundation
import PianoGraderCore

public struct PracticeExercise: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case assessment, notes, slow, fullSpeed, context
        /// The app plays the music; nothing to grade.
        case listen
        /// One note the learner hasn't met: find it and play it (wait mode, one note).
        case newNote
        /// The whole piece at full speed, for stars.
        case perform
        /// "Show me what you can do": the whole piece once, before the lesson; phrases played
        /// cleanly are marked done.
        case placement
    }
    public var kind: Kind
    public var measures: ClosedRange<Int>
    public var tempoPercent: Double
    /// One hand only; nil plays both.
    public var hand: Hand?
    /// The note a `.newNote` step introduces.
    public var note: NoteName?
    /// The phrase this step practises ("Phrase 2"), when it follows a lesson plan.
    public var label: String?
    /// Why the plan skips this step for this learner ("You know these notes"); nil when it doesn't.
    public var skipReason: String?

    public var title: String {
        let base: String
        switch kind {
        case .assessment: base = "Play the whole piece"
        case .notes: base = "Learn note by note"
        case .slow: base = "Slowly, in time"
        case .fullSpeed: base = "Full speed"
        case .context: base = "With surrounding bars"
        case .listen: base = "Listen"
        case .newNote: base = "New note: \(note?.letter ?? "")"
        case .perform: base = "Perform"
        case .placement: base = "Show me what you can do"
        }
        switch hand {
        case .right?: return "Right hand · " + base.lowercasedFirst
        case .left?: return "Left hand · " + base.lowercasedFirst
        default: return base
        }
    }

    /// "Phrase 1 (bars 1–4)", "Bars 1–8", "Bar 3".
    public var whereText: String {
        let bars = measures.count == 1 ? "bar \(measures.lowerBound)" : "bars \(measures.lowerBound)–\(measures.upperBound)"
        guard let label else { return bars.capitalizedFirst }
        return "\(label) (\(bars))"
    }

    /// Played in wait mode (the music waits for each note).
    public var isWaitMode: Bool { kind == .notes || kind == .newNote }
    /// Graded on the clicks.
    public var isTimed: Bool { [.assessment, .slow, .fullSpeed, .context, .perform, .placement].contains(kind) }

    public init(kind: Kind, measures: ClosedRange<Int>, tempoPercent: Double = 100, hand: Hand? = nil,
                note: NoteName? = nil, label: String? = nil, skipReason: String? = nil) {
        self.kind = kind; self.measures = measures; self.tempoPercent = tempoPercent
        self.hand = hand; self.note = note; self.label = label; self.skipReason = skipReason
    }
    /// Identifies a step across rebuilds of a plan (what, where, which hand, how fast).
    public var key: String {
        "\(kind.rawValue)|\(measures.lowerBound)-\(measures.upperBound)|\(hand?.rawValue ?? "")|\(note?.pitch ?? -1)|\(Int(tempoPercent))|\(label ?? "")"
    }
    public func originalMeasure(_ local: Int) -> Int { measures.lowerBound + local - 1 }
    public func printedMeasure(_ local: Int, playOrder: [Int]) -> Int {
        let original = originalMeasure(local)
        return playOrder.indices.contains(original - 1) ? playOrder[original - 1] : original
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Decisions depend only on grading evidence. Language models never advance this engine.
///
/// Two ways through a piece:
/// - **Following a lesson plan** (`plan` given): listen, new notes, each phrase (hands
///   separately, then together, then slowly in time), the phrases joined, the whole piece
///   slowly, then Perform for stars.
/// - **Adaptive** (no plan, after the plan's Perform, or "Assess me instead"): play the whole
///   piece, then practise what went wrong, sized to how far off it was (`PhraseGrade`): a
///   near-perfect run just polishes the slipped bars; timing slips go slowly in time; wrong
///   notes go note by note on those bars only; then assess again.
///
/// Placement ("Show me what you can do") grades each phrase the same way and reshapes its
/// steps. Two failed runs in a row on a timed step drop back one level (full speed → slowly →
/// note by note).
public struct PiecePracticeEngine: Sendable {
    public let measureCount: Int
    public let persona: Persona
    public private(set) var exercise: PracticeExercise
    public private(set) var cleanStreak = 0
    public private(set) var runs = 0
    public private(set) var mastered = false
    /// The plan being followed, or the one the adaptive drills take phrases from.
    public private(set) var plan: LessonPlan?
    /// The plan's steps, in order (empty without a plan).
    public private(set) var steps: [PracticeExercise] = []
    /// Where the learner is in `steps`; nil when not following the plan.
    public private(set) var stepIndex: Int?
    /// Steps of the plan passed (or skipped by the learner) so far.
    public private(set) var completedSteps: Set<Int> = []
    /// Steps the plan leaves out for this learner (they have a `skipReason`); still clickable.
    public var skippedSteps: Set<Int> { Set(steps.indices.filter { steps[$0].skipReason != nil }) }
    /// Stars from the last Perform run.
    public private(set) var lastStars: Int?
    /// How each phrase went in "Show me what you can do" (by phrase index); shapes its steps.
    public private(set) var grades: [Int: PhraseGrade] = [:]
    /// Failed runs in a row on the current timed step.
    public private(set) var failStreak = 0
    /// The last graded run passed (80%+ of the notes, rhythm fine) but had slips to mention.
    public private(set) var lastRunPassedWithSlips = false
    private var queue: [PracticeExercise] = []

    /// Where the learner got to in a planned lesson, to save and resume.
    public struct Progress: Codable, Equatable, Sendable {
        /// Which plan this is for: progress on a different plan isn't restored.
        public var planSignature: String
        public var stepIndex: Int?
        public var completedSteps: [Int]
        /// The current exercise (an adaptive drill, once past the plan).
        public var exercise: PracticeExercise
        public var lastStars: Int?
        public var mastered: Bool
        public var saved: Date
        /// Steps in the plan (nil in progress saved before this was kept).
        public var stepCount: Int?
        /// How each phrase went in "Show me what you can do", and the steps by key (the steps
        /// depend on the grades, so indices alone can't be trusted).
        public var grades: [Int: PhraseGrade]?
        public var completedKeys: [String]?
        public var stepKey: String?

        /// Something has been done: a step passed, a later step reached, a Perform played, or
        /// the plan left for the drills. Opening a lesson and leaving it isn't progress.
        public var isUnderWay: Bool {
            !completedSteps.isEmpty || (stepIndex ?? 1) > 0 || lastStars != nil || mastered
        }
    }

    public var progress: Progress? {
        plan.map { Progress(planSignature: Self.signature($0), stepIndex: stepIndex, completedSteps: completedSteps.sorted(),
                            exercise: exercise, lastStars: lastStars, mastered: mastered, saved: Date(),
                            stepCount: steps.count, grades: grades,
                            completedKeys: completedSteps.sorted().map { steps[$0].key },
                            stepKey: stepIndex.map { steps[$0].key }) }
    }

    /// Picks up where `saved` left off, if it's for this plan. Returns whether it did.
    @discardableResult
    public mutating func restore(_ saved: Progress) -> Bool {
        guard let plan, saved.planSignature == Self.signature(plan) else { return false }
        grades = saved.grades ?? [:]
        steps = Self.steps(for: plan, measureCount: measureCount, persona: persona, grades: grades)
        if let keys = saved.completedKeys {
            completedSteps = Set(steps.indices.filter { keys.contains(steps[$0].key) })
        } else {
            completedSteps = Set(saved.completedSteps.filter { steps.indices.contains($0) })
        }
        lastStars = saved.lastStars
        mastered = saved.mastered
        queue = []
        if let key = saved.stepKey, let i = steps.firstIndex(where: { $0.key == key }) {
            jump(to: i)
        } else if saved.stepKey == nil, let i = saved.stepIndex, steps.indices.contains(i) {
            jump(to: i)
        } else {
            stepIndex = nil
            exercise = saved.exercise
            cleanStreak = 0; runs = 0
        }
        return true
    }

    /// The plan's phrases, hands and new notes, as text: equal for the same plan.
    public static func signature(_ plan: LessonPlan) -> String {
        plan.phrases.map { "\($0.bars.lowerBound)-\($0.bars.upperBound)" }.joined(separator: ",")
            + "|\(plan.handsSeparately)|" + plan.newNotes.map(\.note.name).joined(separator: ",")
    }

    public init(measureCount: Int, persona: Persona = .alex, plan: LessonPlan? = nil) {
        self.measureCount = max(1, measureCount); self.persona = persona
        exercise = PracticeExercise(kind: .assessment, measures: 1...max(1, measureCount))
        if let plan { follow(plan) }
    }

    public var isFollowingPlan: Bool { stepIndex != nil }

    public var needed: Int {
        switch exercise.kind {
        case .notes, .newNote, .listen, .perform: return 1
        default: return persona.drill.cleanRunsNeeded
        }
    }

    // MARK: The plan

    /// The steps for a plan, in teaching order.
    public static func steps(for plan: LessonPlan, measureCount: Int, persona: Persona,
                             grades: [Int: PhraseGrade] = [:]) -> [PracticeExercise] {
        let count = max(1, measureCount)
        let whole = 1...count
        let slow = persona.drill.slowTempoPercent
        let known = plan.familiarity ?? Familiarity()
        var out: [PracticeExercise] = [.init(kind: .placement, measures: whole), .init(kind: .listen, measures: whole)]
        for n in plan.newNotes {
            out.append(.init(kind: .newNote, measures: whole, hand: n.hand, note: n.note))
        }
        for (i, p) in plan.phrases.enumerated() {
            let bars = max(1, min(count, p.bars.lowerBound))...max(1, min(count, p.bars.upperBound))
            // After "Show me what you can do", the phrase's steps fit how it went.
            if let grade = grades[i], grade != .major {
                out += phraseSteps(grade, bars: bars, label: p.label, persona: persona, count: count, plan: plan)
                continue
            }
            let knowsNotes = known.knownPhrases.contains(i) && grades[i] == nil
            if plan.handsSeparately {
                let skip = knowsNotes && known.handsTogether ? "You know these notes and have played both hands together" : nil
                out.append(.init(kind: .notes, measures: bars, hand: .right, label: p.label, skipReason: skip))
                out.append(.init(kind: .notes, measures: bars, hand: .left, label: p.label, skipReason: skip))
            }
            out.append(.init(kind: .notes, measures: bars, label: p.label,
                             skipReason: knowsNotes && known.tempoReached ? "You know these notes" : nil))
            out.append(.init(kind: .slow, measures: bars, tempoPercent: slow, label: p.label))
        }
        let cleanish: (Int) -> Bool = { i in
            switch grades[i] { case .clean?, .minor?: return true; default: return false }
        }
        if plan.phrases.count > 1 {
            for i in 1..<plan.phrases.count {
                let a = plan.phrases[i - 1], b = plan.phrases[i]
                out.append(.init(kind: .slow, measures: max(1, a.bars.lowerBound)...min(count, b.bars.upperBound),
                                 tempoPercent: slow, label: "\(a.label) + \(b.label)",
                                 skipReason: cleanish(i - 1) && cleanish(i) ? "You played both phrases well" : nil))
            }
        }
        if plan.phrases.count > 2 {
            out.append(.init(kind: .slow, measures: whole, tempoPercent: slow,
                             skipReason: plan.phrases.indices.allSatisfy(cleanish) ? "You played the whole piece well" : nil))
        }
        out.append(.init(kind: .perform, measures: whole))
        // No step twice in a row (a one-phrase piece: its slow step is the whole piece).
        return out.enumerated().filter { i, step in
            i == 0 || !(out[i - 1].kind == step.kind && out[i - 1].measures == step.measures && out[i - 1].hand == step.hand)
        }.map(\.element)
    }

    /// A phrase's steps once "Show me what you can do" has graded it.
    static func phraseSteps(_ grade: PhraseGrade, bars: ClosedRange<Int>, label: String, persona: Persona,
                            count: Int, plan: LessonPlan) -> [PracticeExercise] {
        let slow = persona.drill.slowTempoPercent
        switch grade {
        case .clean:
            var steps: [PracticeExercise] = []
            if plan.handsSeparately {
                steps.append(.init(kind: .notes, measures: bars, hand: .right, label: label, skipReason: "You played this phrase cleanly"))
                steps.append(.init(kind: .notes, measures: bars, hand: .left, label: label, skipReason: "You played this phrase cleanly"))
            }
            steps.append(.init(kind: .notes, measures: bars, label: label, skipReason: "You played this phrase cleanly"))
            steps.append(.init(kind: .slow, measures: bars, tempoPercent: slow, label: label, skipReason: "You played this phrase cleanly"))
            return steps
        case .minor(let slipped):
            // Just the slipped bars at full speed, then the phrase.
            return slipped.prefix(3).map { .init(kind: .fullSpeed, measures: $0...$0, label: label) }
                + [.init(kind: .fullSpeed, measures: bars, label: label)]
        case .timing:
            return [.init(kind: .slow, measures: bars, tempoPercent: slow, label: label),
                    .init(kind: .fullSpeed, measures: bars, label: label)]
        case .moderate(let wrong):
            // Note by note only where notes were wrong, then the phrase in time.
            return wrong.prefix(3).map { .init(kind: .notes, measures: $0...$0, label: label) }
                + [.init(kind: .slow, measures: bars, tempoPercent: slow, label: label),
                   .init(kind: .fullSpeed, measures: bars, label: label)]
        case .major:
            return []
        }
    }

    /// Steps again from the plan and the grades, keeping what's done and where the learner is.
    private mutating func rebuild() {
        guard let plan else { return }
        let done = Set(completedSteps.map { steps[$0].key })
        let current = stepIndex.map { steps[$0].key }
        steps = Self.steps(for: plan, measureCount: measureCount, persona: persona, grades: grades)
        completedSteps = Set(steps.indices.filter { done.contains(steps[$0].key) })
        stepIndex = current.flatMap { key in steps.firstIndex { $0.key == key } }
    }

    /// Starts following `plan` from its first step.
    public mutating func follow(_ plan: LessonPlan) {
        self.plan = plan
        grades = [:]
        steps = Self.steps(for: plan, measureCount: measureCount, persona: persona)
        completedSteps = []
        queue = []; mastered = false; lastStars = nil
        jump(to: steps.indices.first { steps[$0].skipReason == nil } ?? 0)
    }

    /// Goes to step `index` of the plan (the checklist).
    public mutating func jump(to index: Int) {
        guard steps.indices.contains(index) else { return }
        stepIndex = index
        exercise = steps[index]
        cleanStreak = 0; runs = 0; failStreak = 0
    }

    /// A step with nothing to grade (listen) is done.
    public mutating func completeStep() {
        guard let i = stepIndex else { return }
        completedSteps.insert(i)
        nextStep()
    }

    /// Leaves the plan for the adaptive loop: play the whole piece to find what to practise.
    public mutating func assessInstead() {
        stepIndex = nil
        reassess()
    }

    /// The next step not yet done and not skipped for this learner.
    private mutating func nextStep() {
        guard let i = stepIndex else { return }
        if let next = steps.indices.first(where: { $0 > i && !completedSteps.contains($0) && steps[$0].skipReason == nil }) {
            jump(to: next)
        } else {
            stepIndex = nil
            exercise = .init(kind: .assessment, measures: 1...measureCount)
            cleanStreak = 0; runs = 0
        }
    }

    // MARK: Adaptive

    public mutating func reassess() {
        queue = []; cleanStreak = 0; runs = 0; mastered = false
        stepIndex = nil
        exercise = PracticeExercise(kind: .assessment, measures: 1...measureCount)
    }
    public mutating func learnNotes() { reassess(); exercise.kind = .notes }

    /// The learner's own choice: work on these bars. Each run of neighbouring bars (up to four)
    /// note by note, slowly in time, at full speed, then with the bars around it; then the
    /// whole piece again.
    public mutating func focus(on bars: [Int]) {
        let marked = Set(bars).filter { (1...measureCount).contains($0) }.sorted()
        guard !marked.isEmpty else { return }
        var groups: [ClosedRange<Int>] = []
        for b in marked {
            if let last = groups.last, b == last.upperBound + 1, last.count < 4 {
                groups[groups.count - 1] = last.lowerBound...b
            } else {
                groups.append(b...b)
            }
        }
        stepIndex = nil; mastered = false
        let label = Self.focusLabel
        queue = groups.flatMap { g -> [PracticeExercise] in
            var steps: [PracticeExercise] = [
                .init(kind: .notes, measures: g, label: label),
                .init(kind: .slow, measures: g, tempoPercent: persona.drill.slowTempoPercent, label: label),
                .init(kind: .fullSpeed, measures: g, label: label),
            ]
            let around = max(1, g.lowerBound - 1)...min(measureCount, g.upperBound + 1)
            if around != g { steps.append(.init(kind: .context, measures: around)) }
            return steps
        }
        advance()
    }

    public static let focusLabel = "Your marked bars"
    public mutating func skip() {
        if let i = stepIndex { completedSteps.insert(i); nextStep() } else { advance() }
    }

    /// Records a graded run of the current exercise. `stars`: the Perform run's stars.
    public mutating func record(_ report: GradeReport, replays: Int = 0, completedNotes: Bool = false, stars: Int? = nil) {
        lastRunPassedWithSlips = !exercise.isWaitMode && report.timing != nil
            && RemediationPlanner.passedWithSlips(report, replays: replays)
        if exercise.kind == .listen { completeStep(); return }
        if exercise.kind == .placement { place(after: report); return }
        if exercise.kind == .perform {
            lastStars = stars
            // A passing run (80%+ of the notes right and on time, rhythm fine), whatever the stars.
            mastered = report.timing != nil && RemediationPlanner.isClean(report, replays: replays)
            if let i = stepIndex { completedSteps.insert(i) }
            if mastered { completedSteps = Set(steps.indices) }
            stepIndex = nil
            if mastered {
                exercise = .init(kind: .assessment, measures: 1...measureCount)
                cleanStreak = 0; runs = 0
            } else {
                planDrills(after: report)
            }
            return
        }
        if exercise.kind == .assessment {
            mastered = RemediationPlanner.isClean(report, replays: replays) && report.timing != nil
            // Passed: the plan's steps are all done (the checklist shouldn't look like a restart).
            guard !mastered else { completedSteps = Set(steps.indices); return }
            planDrills(after: report)
            return
        }
        runs += 1
        let clean = exercise.isWaitMode ? completedNotes : RemediationPlanner.isClean(report, replays: replays) && report.timing != nil
        cleanStreak = clean ? cleanStreak + 1 : 0
        failStreak = clean || exercise.isWaitMode ? 0 : failStreak + 1
        if failStreak >= 2, let easier = easier(than: exercise, after: report) {
            dropBack(to: easier)
            return
        }
        if cleanStreak >= needed || (persona.drill.maxRunsPerStep.map { runs >= $0 } ?? false) {
            if let i = stepIndex {
                completedSteps.insert(i)
                nextStep()
            } else {
                advance()
            }
        }
    }

    /// "Show me what you can do": every step on a phrase played cleanly (no wrong, missed,
    /// extra, early or late notes in its bars) is done, and so is a new note met only in clean
    /// phrases. All clean and passed at full speed: straight to Perform. Then the first step
    /// still to do.
    private mutating func place(after report: GradeReport) {
        guard let plan, let here = stepIndex else { return }
        completedSteps.insert(here)
        var graded: [Int: PhraseGrade] = [:]
        // A passing run at full speed (80%+ of the notes right and on time) counts as clean on
        // every phrase that passes by itself (a few slips): straight on, not back into the lesson.
        let passedRun = RemediationPlanner.isClean(report, replays: 0) && report.timing != nil
        for (i, p) in plan.phrases.enumerated() {
            let grade = PhraseGrade.grade(p.bars, in: report)
            let passes = passedRun && RemediationPlanner.passScore(report, bars: p.bars) >= RemediationPlanner.passingScore
            graded[i] = passes ? .clean : grade
        }
        grades = graded
        rebuild()
        let cleanBars = Set(plan.phrases.enumerated().filter { graded[$0.offset] == .clean }.flatMap { Array($0.element.bars) })
        let allClean = cleanBars.count >= measureCount && report.timing != nil
        for (i, step) in steps.enumerated() where !completedSteps.contains(i) {
            switch step.kind {
            case .newNote:
                let bars = plan.newNotes.first { $0.note == step.note }?.bars ?? []
                if !bars.isEmpty, Set(bars).isSubset(of: cleanBars) { completedSteps.insert(i) }
            case .listen:
                if allClean { completedSteps.insert(i) }
            default:
                break
            }
        }
        if let first = steps.indices.first(where: { !completedSteps.contains($0) && steps[$0].skipReason == nil }) {
            jump(to: first)
        } else {
            jump(to: steps.count - 1)
        }
    }

    /// The practice after a whole-piece run that wasn't good enough, sized to how far off it
    /// was. Nearly there (90%+ of the notes, timing measured): polish the slipped bars at full
    /// speed and go again. Otherwise the phrase around the worst bar, by its grade: a slip or
    /// two → those bars, then the phrase; timing → slowly in time, then full speed; wrong notes
    /// → note by note on those bars only, then in time; most notes wrong → note by note from
    /// the start of the bar.
    private mutating func planDrills(after report: GradeReport) {
        let whole = 1...measureCount
        let slow = persona.drill.slowTempoPercent
        queue = []
        let overall = PhraseGrade.accuracy(whole, in: report)
        let slipped = Array(Set(report.results.filter { $0.kind != .correct }.map(\.position.measure))).sorted()
        if overall >= 0.9, report.timing != nil, !slipped.isEmpty {
            queue = slipped.prefix(4).map { .init(kind: .fullSpeed, measures: $0...$0) }
            advance()
            return
        }
        let worst = RemediationPlanner.worstMeasure(in: [report]).map { min(measureCount, max(1, $0)) }
        let phrases = plan?.phrases.map(\.bars) ?? stride(from: 1, through: measureCount, by: 4).map { $0...min(measureCount, $0 + 3) }
        let index = worst.flatMap { w in phrases.firstIndex { $0.contains(w) } }
            ?? phrases.firstIndex { PhraseGrade.grade($0, in: report) != .clean }
        guard let index else {
            // Nothing wrong with the notes (timing couldn't be measured, say): the piece in time.
            queue = [.init(kind: .slow, measures: whole, tempoPercent: slow), .init(kind: .fullSpeed, measures: whole)]
            advance()
            return
        }
        let range = max(1, phrases[index].lowerBound)...min(measureCount, phrases[index].upperBound)
        let label = plan?.phrases[index].label
        let context = max(1, range.lowerBound - 1)...min(measureCount, range.upperBound + 1)
        switch PhraseGrade.grade(range, in: report) {
        case .clean, .timing:
            queue = [.init(kind: .slow, measures: range, tempoPercent: slow, label: label),
                     .init(kind: .fullSpeed, measures: range, label: label)]
        case .minor(let bars):
            queue = bars.prefix(3).map { .init(kind: .fullSpeed, measures: $0...$0, label: label) }
                + [.init(kind: .fullSpeed, measures: range, label: label)]
        case .moderate(let bars):
            queue = bars.prefix(3).map { .init(kind: .notes, measures: $0...$0, label: label) }
                + [.init(kind: .slow, measures: range, tempoPercent: slow, label: label),
                   .init(kind: .fullSpeed, measures: range, label: label)]
        case .major:
            let bar = worst ?? range.lowerBound
            queue = [.init(kind: .notes, measures: bar...bar, label: label),
                     .init(kind: .slow, measures: range, tempoPercent: slow, label: label),
                     .init(kind: .fullSpeed, measures: range, label: label)]
        }
        if context != range { queue.append(.init(kind: .context, measures: context)) }
        advance()
    }

    /// One level easier than `step`, after two failed runs: full speed → slowly in time;
    /// slowly → note by note on the bars that went wrong (or the whole step when it's short).
    func easier(than step: PracticeExercise, after report: GradeReport) -> PracticeExercise? {
        switch step.kind {
        case .fullSpeed, .context:
            return .init(kind: .slow, measures: step.measures, tempoPercent: persona.drill.slowTempoPercent,
                         hand: step.hand, label: step.label)
        case .slow:
            let wrong = Array(Set(report.results.filter { $0.kind != .correct }.map { step.originalMeasure($0.position.measure) })).sorted()
            let bars = wrong.first.map { $0...(wrong.last ?? $0) } ?? step.measures
            return .init(kind: .notes, measures: bars.count <= 4 ? bars : bars.lowerBound...bars.lowerBound + 3,
                         hand: step.hand, label: step.label)
        default:
            return nil
        }
    }

    /// Puts an easier step before the current one; the current one comes back after it.
    private mutating func dropBack(to easier: PracticeExercise) {
        if let i = stepIndex {
            steps.insert(easier, at: i)
            completedSteps = Set(completedSteps.map { $0 >= i ? $0 + 1 : $0 })
            jump(to: i)
        } else {
            queue.insert(exercise, at: 0)
            exercise = easier
            cleanStreak = 0; runs = 0; failStreak = 0
        }
    }

    private mutating func advance() {
        cleanStreak = 0; runs = 0; failStreak = 0
        exercise = queue.isEmpty ? .init(kind: .assessment, measures: 1...measureCount) : queue.removeFirst()
    }
}

public struct TutorAttemptContext: Codable, Sendable {
    public var exercise: PracticeExercise
    public var actualTempoPercent: Double
    public var mode: String
    public var printedMeasures: [Int]
    /// Stars, for a Perform run.
    public var stars: Int?
    public init(exercise: PracticeExercise, actualTempoPercent: Double, mode: String, printedMeasures: [Int], stars: Int? = nil) {
        self.exercise = exercise; self.actualTempoPercent = actualTempoPercent
        self.mode = mode; self.printedMeasures = printedMeasures; self.stars = stars
    }
}
