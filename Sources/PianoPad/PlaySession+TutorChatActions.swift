#if os(macOS)
import Foundation
import PianoGraderCore
import PianoLessons

extension PlaySession {
    func startPreparedTutorChatExercise() {
        guard canChatWithTutor, tutorChatAwaitingStart, phase == .waiting,
              tutorAttempt?.isTimed == true, !tutorChatBusy else { return }
        startTimedRun()
    }

    func finishTutorChatTake() {
        guard canChatWithTutor, phase == .recording, noteCount > 0,
              playAlongState != .countIn else { return }
        finishTake()
    }

    /// Pausing cancels pending decisions without throwing away a take in progress.
    func pauseTutorChatCoaching() {
        tutorChatCoaching = false
        tutorChatCoachingFromDefault = false
        stopTutorChat()
    }

    /// Coaching after each take is on by default (the ✦ button); pressing it remembers the choice.
    static let tutorChatCoachesByDefaultKey = "PianoPad.tutor.coachAfterTakes"
    var tutorChatCoachesByDefault: Bool {
        get { UserDefaults.standard.object(forKey: Self.tutorChatCoachesByDefaultKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.tutorChatCoachesByDefaultKey) }
    }

    /// The ✦ button: on or off now, and the same next time the chat opens.
    func setTutorChatCoaching(_ on: Bool) {
        tutorChatCoachesByDefault = on
        if on {
            tutorChatCoaching = true
            tutorChatCoachingFromDefault = false
        } else {
            pauseTutorChatCoaching()
        }
    }

    /// The chat is showing: coach after each take, unless the learner turned that off.
    func applyTutorChatCoachingDefault() {
        guard canChatWithTutor, !tutorChatCoaching, tutorChatCoachesByDefault else { return }
        tutorChatCoaching = true
        tutorChatCoachingFromDefault = true
    }

    /// The chat was closed. Coaching that only came from the default stops, so the Lesson tab
    /// and Learn lessons give their own feedback again; coaching the tutor started carries on.
    func leaveTutorChat() {
        guard tutorChatCoachingFromDefault, tutorChatCoaching, !tutorChatBusy,
              tutorChatQueuedActions.isEmpty, tutorChatPendingObservation == nil, !tutorChatAwaitingStart else { return }
        tutorChatCoaching = false
        tutorChatCoachingFromDefault = false
    }

    func tutorChatDidGrade() {
        guard canChatWithTutor, let report = tutorDisplayReport else { return }
        let scope = tutorAttempt.map { "\($0.title), printed bars \(tutorPrinted($0))" } ?? "current passage"
        let evidence = "\(tutorTitle), \(scope), \(mode.rawValue), \(Int(tempoPercent))% speed:\n" + Self.tutorChatGradeText(report)
        tutorChatRecentGrades = Array((tutorChatRecentGrades + [evidence]).suffix(3))
        guard tutorChatCoaching, !lastTake.isEmpty, !advanceTutorChatPlan() else { return }
        tutorChatObserve("Take graded · \(tutorTitle) · \(Int(report.notes.score * 100))% notes",
                         question: "The grader has finished a real take. Using the latest grader evidence and musical goal, tell me like my teacher what went well and the one thing to work on, in plain words without numbers, and select the next practice action. Do not claim mastery from wait mode or a slowed run.")
    }

    /// A demonstration ended: a passage, or the tutor's `playNotes`. A queued plan goes on.
    func tutorChatDidListen() {
        guard canChatWithTutor, !advanceTutorChatPlan(), tutorChatCoaching, tutor != nil else { return }
        tutorChatObserve("Demonstration finished",
                         question: "The app finished demonstrating the passage. Start its next lesson step with continueLesson, or choose practicePassage for the demonstrated bars. Do not replay the demonstration unless the learner asked.")
    }

    func tutorChatObserve(_ label: String, question: String) {
        guard canChatWithTutor, tutorChatCoaching else { return }
        tutorChatPendingObservation = TutorChatObservation(label: label, question: question,
                                                          context: tutorChatContext(for: question), scoreID: scoreID)
        flushTutorChatObservation()
    }

    func flushTutorChatObservation() {
        guard canChatWithTutor, tutorChatCoaching, !tutorChatBusy,
              let event = tutorChatPendingObservation else { return }
        tutorChatPendingObservation = nil
        guard event.scoreID == scoreID else { return }
        requestTutorChat(event.question, context: event.context, observation: event.label, scoreID: event.scoreID)
    }

    /// Fewer notes than this in a recording take: nothing worth keeping for the grader.
    static let tutorChatEmptyTakeNotes = 2

    /// Throws away a recording take with no real playing in it, so a tutor action can run.
    /// False (and the take is kept) once the learner has played.
    func discardTutorChatEmptyTake() -> Bool {
        guard phase == .recording, noteCount < Self.tutorChatEmptyTakeNotes else { return false }
        if isPlayingAlong { stopPlayAlong(discard: true) }
        resetTake()
        return true
    }

    /// Only these bounded player operations can be requested by model output.
    @discardableResult
    func applyTutorChatAction(_ action: TutorChatAction) -> String {
        tutorChatActionRan = false
        // The tutor is steering now, so its coaching stays on when the chat is closed.
        tutorChatCoachingFromDefault = false
        guard canChatWithTutor || (tutorChatIsChild && TutorChildPrompts.actions.contains(action.kind)) else {
            return "Tutor actions are available only for the active adult learner."
        }
        // Never replace an ungraded performance or cut off a demonstration with an old decision.
        // A take with no real playing in it (a stray note, a count-in) isn't a performance.
        let keepsTake: Set<TutorChatAction.Kind> = [.gradeTake, .stop, .setGoal, .setTempo, .searchLibrary, .highlight]
        var setAside = false
        if phase == .recording && !keepsTake.contains(action.kind) && !discardTutorChatEmptyTake() {
            // Asked to hear it: a teacher stops and plays it, so the half-played take is set aside.
            guard Self.tutorChatDemonstrations.contains(action.kind), !isAuditioning else {
                return "A take is still recording. Finish it with Grade, or ask me to grade it, before changing the exercise."
            }
            if isPlayingAlong { stopPlayAlong(discard: true) }
            discardTake()
            setAside = true
        }
        if isAuditioning && ![.stop, .setGoal, .searchLibrary, .highlight].contains(action.kind) {
            return "The demonstration is still playing. Let it finish, or stop it before changing exercises."
        }
        let outcome = performTutorChatAction(action)
        return setAside ? "Your unfinished take was set aside (not graded) so I could play. " + outcome : outcome
    }

    /// Demonstrations the learner can ask for mid-take: they stop the take instead of being refused.
    static let tutorChatDemonstrations: Set<TutorChatAction.Kind> = [.listenPassage, .playNotes]

    private func performTutorChatAction(_ action: TutorChatAction) -> String {
        switch action.kind {
        case .setTempo:
            guard let speed = action.tempoPercent, speed.isFinite, (25...100).contains(speed) else {
                return "Choose a practice speed from 25% to 100%."
            }
            guard tutor != nil || reference?.notes.isEmpty == false else { return "Open a piece before changing its practice speed." }
            _ = tutor?.setExerciseTempo(speed)
            _ = tutorBeforeAttempt?.setExerciseTempo(speed)
            tutorAttempt?.tempoPercent = speed
            tempoPercent = speed
            return ran("Set this passage to \(Int(speed))% speed. Your take has not been graded.")

        case .setGoal:
            guard TutorChat.clean(action.goal ?? "") != nil else { return "No musical goal was provided." }
            if let problem = Self.tutorChatGoalDateProblem(action.goalDate) { return problem }
            saveChatGoal(from: action)
            return ran("Goal saved: \(learnerSettings.tutorGoal!)"
                + (learnerSettings.tutorGoalDate.map { ", by \(Self.tutorChatDay($0))" } ?? "") + ".")

        case .openCalibration:
            guard calibrationPrompt == nil else { return "Calibration is already running; follow its prompts." }
            return offer("Calibrate the mic (10 s)", action)

        case .switchInput:
            guard let source = action.input.flatMap(InputSource.init(rawValue:)) else {
                return "Choose an input: midi, microphone or computerKeyboard. Nothing changed."
            }
            guard source != chosenInput else { return ran("You're already playing with the \(Self.tutorChatInputName(source)).") }
            if source == .midi && midiSources.isEmpty {
                return "No Bluetooth MIDI piano is connected. Connect one from the Practice tab's ⋯ menu first. Nothing changed."
            }
            return offer("Use the \(Self.tutorChatInputName(source))", action)

        case .openSettings:
            guard let panel = action.section.flatMap(TutorChatPanel.init(rawValue:)) else {
                return "Choose settings to open: input, practice or ai. Nothing changed."
            }
            return offer(panel == .input ? "Open input settings" : panel == .practice ? "Open practice settings" : "Open AI settings", action)

        case .markPlayedRight:
            return markTutorChatTakePlayedRight()

        case .planSession:
            guard let plan = TutorSessionPlan(minutes: action.minutes, steps: action.planSteps) else {
                return "A plan needs 2–\(TutorSessionPlan.stepLimit) steps and 5–120 minutes. Nothing was saved."
            }
            setTutorChatSessionPlan(plan)
            return ran("Saved today's plan: \(plan.steps.count) steps, \(plan.minutes) minutes. Tick them off in the chat.")

        case .gradeTake:
            guard phase == .recording, noteCount > 0, playAlongState != .countIn else {
                return "No played take is ready to grade. Start practice and play the passage first."
            }
            tutorChatOffersGrade = true
            tutorChatCoaching = true
            return ran("Press Grade take when you've finished playing. Changing settings does not grade your take.")

        case .stop:
            pauseTutorChatCoaching()
            stopListening()
            if phase == .recording && noteCount > 0 {
                stopPlayAlong(discard: false)
                tutorChatOffersGrade = true
                return ran("Coaching paused. Your ungraded take is kept; press Grade take when you're finished.")
            }
            endTutoring()
            return ran("Coaching paused. No take was graded.")

        case .openLesson:
            guard let id = action.lessonID, let unit = Self.unitOne?.unit,
                  let page = unit.page(id), let learner else { return "That lesson is not available." }
            let completed = learnerStore.history(for: learner.id).completedPages(unit: unit.id)
            guard unit.isUnlocked(id, completed: completed) else { return "That lesson is still locked; choose an available lesson." }
            saveChatGoal(from: action)
            tutorChatCoaching = true
            tutorChatFocus = "Lesson: \(page.title)"
            tutorChatPreservesConversation = true
            defer { tutorChatPreservesConversation = false }
            lessonRunner.selectCourse(.piano)
            lessonRunner.arrive()
            openStockLesson(id)
            guard lessonRunner.page?.id == id else { return "The lesson could not be opened. Your practice setup was kept." }
            return ran("Opened \(page.title). I'll follow the graded attempts in this lesson. Open Tutor in the header to keep chatting.")

        case .startLesson:
            guard !isInLesson, reference?.notes.isEmpty == false else { return "Open a piece in Practice before starting its tutor lesson." }
            saveChatGoal(from: action)
            tutorChatCoaching = true
            tutorChatFocus = "Learn \(tutorTitle) with its lesson plan."
            if tutor == nil {
                beginTutoring(planLesson: true, ignoreReadiness: true)
            } else if !tutorPlanning {
                startTutorExercise(waitForReady: true)
            }
            return ran(tutorPlanning ? "Planning a lesson for \(tutorTitle). I'll prepare its first step when the plan is ready."
                : tutorChatAwaitingStart ? "The next step is ready. Press Start practice when you're ready."
                : "Started the next step for \(tutorTitle).")

        case .continueLesson:
            guard !isInLesson, tutor != nil, !tutorPlanning else { return "No piece-tutor step is ready. Start a lesson first, or continue the open Learn lesson with its controls." }
            tutorChatCoaching = true
            startTutorExercise(waitForReady: true)
            return ran(tutorChatAwaitingStart ? "The next step is ready. Press Start practice when you're ready for the count-in."
                : "Started \(tutorAttempt?.title ?? "the demonstration") for \(tutorTitle).")

        case .practicePassage, .listenPassage:
            guard !isInLesson, let full = tutorFullReference ?? reference, !full.notes.isEmpty else {
                return "Open a piece in Practice to practise a specific passage. Finish or leave the Learn lesson first."
            }
            guard let start = action.fromBar, let end = action.toBar, start >= 1, end >= start,
                  end - start < 16, let played = tutorChatPlayedRange(start...end, full: full) else {
                return "That passage is outside the open piece or spans more than 16 bars. No player settings changed."
            }
            let speed = action.tempoPercent ?? 60
            guard speed.isFinite, (25...100).contains(speed) else { return "Choose a practice speed from 25% to 100%. No player settings changed." }
            // One track: a one-hand request can only mean all of its notes.
            let oneTrack = action.hand != nil && action.hand != .both && !full.hasTwoHands
            let hand: Hand? = action.hand == .both || oneTrack ? nil : action.hand
            if let hand, full.measures(played).hand(hand).notes.isEmpty { return "The selected passage has no notes for that hand." }
            let kind: PracticeExercise.Kind = action.kind == .listenPassage ? .listen : action.mode == .timed ? .slow : .notes
            guard startTutorChatPractice(PracticeExercise(kind: kind, measures: played, tempoPercent: speed, hand: hand, label: "Your practice passage"),
                                         focus: "Practise printed bars \(start)–\(end), hand \(hand?.rawValue ?? "LR"), toward the learner's goal. Keep this passage until grading supports moving on.")
            else { return "This practice passage could not be started." }
            saveChatGoal(from: action)
            let mode = action.kind == .listenPassage ? "demonstration" : action.mode == .timed ? "in time" : "note by note"
            return ran("\(tutorChatAwaitingStart ? "Prepared" : "Started") bars \(start)–\(end), \(oneTrack ? "all its notes (the file has one track)" : hand?.rawValue ?? "both hands"), \(Int(speed))%, \(mode). "
                + (tutorChatAwaitingStart ? "Press Start practice when you're ready." : "Play when you're ready; I'll review the graded take."))

        // Library and navigation (PlaySession+TutorLibrary).
        case .searchLibrary: return checked(MainActor.assumeIsolated { tutorChatSearchLibrary(action) })
        case .openPiece: return checked(MainActor.assumeIsolated { tutorChatOpenPiece(action) })
        case .previewPiece: return checked(MainActor.assumeIsolated { tutorChatPreviewPiece(action) })
        case .openBookPage: return checked(MainActor.assumeIsolated { tutorChatOpenBookPage(action) })
        case .practiceExercise:
            return practiceTutorChatExercise(action)

        case .playNotes:
            guard let names = action.notes, !names.isEmpty else { return "No notes were given to play." }
            var chords: [[Int]] = []
            for token in names {
                var pitches: [Int] = []
                for part in token.split(separator: "+") {
                    guard let note = NoteName(String(part)), Self.keyboardRange.contains(note.pitch) else {
                        return "\(part) is not a note on the keyboard (C2–C6). Nothing was played."
                    }
                    pitches.append(note.pitch)
                }
                guard !pitches.isEmpty else { return "\(token) is not a note name. Nothing was played." }
                chords.append(pitches)
            }
            guard chords.joined().count <= TutorChatAction.playNotesLimit else {
                return "I can play at most \(TutorChatAction.playNotesLimit) notes at a time. Nothing was played."
            }
            let bpm = action.tempoBPM ?? 80
            guard bpm.isFinite, (30...200).contains(bpm) else { return "Choose a tempo from 30 to 200 BPM. Nothing was played." }
            guard auditionNotes(chords, bpm: bpm, onFinish: { [weak self] in self?.tutorChatDidListen() }) else {
                return "The piano couldn't play just now. Check that sound output is available."
            }
            return ran("Playing \(names.joined(separator: " ")) at \(Int(bpm)) BPM; watch the keys light up.")

        case .highlight:
            let bars = action.bars ?? [], names = action.keys ?? []
            guard !bars.isEmpty || !names.isEmpty else { return "Name the bars or keys to show." }
            guard bars.count <= 16, names.count <= 16 else { return "I can show at most 16 bars and 16 keys at once." }
            guard !isInLesson else { return "Highlights show in Practice. Finish or leave the Learn lesson first." }
            var keys = Set<Int>()
            for name in names {
                guard let note = NoteName(name), Self.keyboardRange.contains(note.pitch) else {
                    return "\(name) is not a key on the keyboard (C2–C6). Nothing was highlighted."
                }
                keys.insert(note.pitch)
            }
            if !bars.isEmpty {
                let printed = tutorChatPrintedBars
                if let missing = bars.first(where: { !printed.contains($0) }) {
                    return "Bar \(missing) is not in the open piece. Nothing was highlighted."
                }
            }
            showTutorChatHighlight(bars: Set(bars), keys: keys)
            let shown = [bars.isEmpty ? nil : "bar\(bars.count == 1 ? "" : "s") \(bars.map(String.init).joined(separator: ", "))",
                         names.isEmpty ? nil : names.joined(separator: " ")].compactMap { $0 }
            return ran("Highlighted \(shown.joined(separator: " and ")).")

        case .startEarTraining, .startSightReading:
            return openTutorChatCourse(ear: action.kind == .startEarTraining, level: action.level)
        }
    }

    // MARK: C3 · Demonstrate and generate

    /// How long a `highlight` stays up.
    static let tutorChatHighlightSeconds = 4.0

    func showTutorChatHighlight(bars: Set<Int>, keys: Set<Int>) {
        tutorChatHighlightBars = bars
        tutorChatHighlightKeys = keys
        let id = UUID()
        tutorChatHighlightID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tutorChatHighlightSeconds) { [weak self] in
            guard let self, self.tutorChatHighlightID == id else { return }
            self.tutorChatHighlightBars = []
            self.tutorChatHighlightKeys = []
        }
    }

    /// The open piece's printed bar numbers.
    var tutorChatPrintedBars: Set<Int> {
        guard let full = tutorFullReference ?? reference, full.measureCount > 0 else { return [] }
        return Set((1...full.measureCount).map { passage?.printedMeasure(forPlayed: $0) ?? $0 })
    }

    /// Generates the exercise (the model never writes its notes), opens it as the practice
    /// piece with its fingering, and prepares one graded repetition of all of it.
    private func practiceTutorChatExercise(_ action: TutorChatAction) -> String {
        guard !isInLesson else { return "Finish or leave the Learn lesson before starting an exercise." }
        guard let raw = action.exercise, let kind = ExerciseGenerator.Kind(rawValue: raw) else {
            return "Choose an exercise: \(ExerciseGenerator.Kind.allCases.map(\.rawValue).joined(separator: ", "))."
        }
        guard let key = action.key.flatMap(ExerciseGenerator.Key.init) else { return "Name the key for the exercise, like G, F# or Bb minor." }
        let octaves = action.octaves ?? 1
        guard (1...2).contains(octaves) else { return "Exercises span 1 or 2 octaves." }
        let speed = action.tempoPercent ?? 60
        guard speed.isFinite, (25...100).contains(speed) else { return "Choose a practice speed from 25% to 100%. No player settings changed." }
        let exercise: ExerciseGenerator.Exercise
        do {
            exercise = try ExerciseGenerator.generate(.init(kind: kind, key: key, octaves: octaves, hand: action.hand ?? .right))
        } catch {
            return "That exercise doesn't fit on the keyboard (C2–C6). Try one octave or one hand."
        }
        guard let url = writeTutorChatExercise(exercise) else { return "The exercise could not be prepared. No player settings changed." }
        let written = Transcriber().transcribe(exercise.sequence, title: exercise.title)
        // The generator's fingering, as printed fingering on each staff (right hand on top).
        let printed = exercise.fingering.map { note in
            PrintedFinger(staff: note.hand == .left && written.staves.count > 1 ? 1 : 0, quarter: note.quarter, finger: note.finger)
        }
        tutorChatPreservesConversation = true
        defer { tutorChatPreservesConversation = false }
        guard loadReference(url, remember: false, writtenScore: written, printedFingering: printed, title: exercise.title),
              let full = reference, full.measureCount > 0 else { return "The exercise could not be opened." }
        let mode = action.mode == .timed ? "in time" : "note by note"
        guard startTutorChatPractice(PracticeExercise(kind: action.mode == .timed ? .slow : .notes, measures: 1...full.measureCount,
                                                      tempoPercent: speed, hand: nil, label: exercise.title),
                                     focus: "Practise the generated exercise \(exercise.title) with its printed fingering. Judge it only from the grader.")
        else { return "The exercise could not be started." }
        saveChatGoal(from: action)
        return ran("\(tutorChatAwaitingStart ? "Prepared" : "Started") \(exercise.title), \(Int(speed))%, \(mode). "
            + (tutorChatAwaitingStart ? "Press Start practice when you're ready." : "Play when you're ready; I'll review the graded take."))
    }

    /// Generated exercises are saved like small MIDI files, one per kind, key, range and hand.
    private func writeTutorChatExercise(_ exercise: ExerciseGenerator.Exercise) -> URL? {
        let folder = BookLibrary.support.appendingPathComponent("TutorExercises", isDirectory: true)
        let name = exercise.title.map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
            .replacingOccurrences(of: "#", with: "sharp")
        let url = folder.appendingPathComponent("\(name).mid")
        let music = exercise.sequence
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try MIDIFile.write(notes: music.notes, tempoBPM: music.initialTempoBPM, timeSignature: music.timeSignature,
                               keySignature: music.keySignature).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// One practice repetition of `exercise` on the open piece, replacing any prepared one.
    private func startTutorChatPractice(_ exercise: PracticeExercise, focus: String) -> Bool {
        if tutor == nil { beginTutoring() }
        guard var engine = tutor, engine.selectExercise(exercise) else { return false }
        tutorLeaveAttempt()
        tutor = engine
        tutorPlanning = false
        tutorPlanTask?.cancel(); tutorPlanID = UUID()
        tutorChatCoaching = true
        tutorChatFocus = focus
        startTutorExercise(waitForReady: true)
        return true
    }

    /// The ear-training or sight-reading course, at the learner's next unlocked page (in
    /// `level` when given). Locked pages stay locked.
    private func openTutorChatCourse(ear: Bool, level: Int?) -> String {
        guard let learner else { return "Choose a learner first." }
        let unit = ear ? EarLessonCourse.unit : SightReadingCourse.unit
        let course = ear ? "ear training" : "sight reading"
        let completed = learnerStore.history(for: learner.id).completedPages(unit: unit.id)
        var pages = unit.pages
        if let level {
            pages = pages.filter { $0.title.hasPrefix("Level \(level) ·") }
            guard !pages.isEmpty else { return "There is no \(course) level \(level)." }
        }
        let open = pages.filter { LessonRunner.unlockAllPages || unit.isUnlocked($0.id, completed: completed) }
        guard let page = open.first(where: { !completed.contains($0.id) }) ?? open.last else {
            return "That \(course) level is still locked; finish the earlier levels first."
        }
        tutorChatPreservesConversation = true
        defer { tutorChatPreservesConversation = false }
        tutorChatFocus = "\(course.capitalized): \(page.title)"
        lessonRunner.selectCourse(ear ? .ear : .sight)
        openStockLesson(page.id)
        guard lessonRunner.page?.id == page.id else { return "The \(course) course could not be opened. Your practice setup was kept." }
        return ran("Opened \(course): \(page.title). Open Tutor in the header to keep chatting.")
    }

    /// A successful outcome: the plan may go on to its next step.
    private func ran(_ outcome: String) -> String {
        tutorChatActionRan = true
        return outcome
    }

    private func checked(_ result: (outcome: String, ran: Bool)) -> String {
        result.ran ? ran(result.outcome) : result.outcome
    }

    private func saveChatGoal(from action: TutorChatAction) {
        guard let goal = TutorChat.clean(action.goal ?? "") else { return }
        learnerSettings.tutorGoal = String(goal.prefix(500))
        // A new goal without a date drops the old goal's date.
        learnerSettings.tutorGoalDate = Self.tutorChatGoalDateProblem(action.goalDate) == nil
            ? action.goalDate.flatMap(Self.tutorChatParseDay) : nil
        saveLearnerSettings()
    }

    // MARK: C5 · App help

    /// Shows the change as a button; the learner's tap runs it (`confirmTutorChatOffer`).
    private func offer(_ label: String, _ action: TutorChatAction) -> String {
        tutorChatConfirmation = TutorChatConfirmation(label: label, action: action)
        return ran("Offered: \(label). Nothing changes until you press the button.")
    }

    /// The learner pressed the offered button.
    func confirmTutorChatOffer() {
        guard canChatWithTutor, let offer = tutorChatConfirmation else { return }
        tutorChatConfirmation = nil
        switch offer.action.kind {
        case .openCalibration:
            startCalibration()
        case .switchInput:
            if let source = offer.action.input.flatMap(InputSource.init(rawValue:)) { setInput(source) }
        case .openSettings:
            tutorChatOpenPanel = offer.action.section.flatMap(TutorChatPanel.init(rawValue:))
        default:
            return
        }
        tutorChat.observe("Done: \(offer.label).")
        saveTutorChat()
    }

    func declineTutorChatOffer() { tutorChatConfirmation = nil }

    static func tutorChatInputName(_ source: InputSource) -> String {
        switch source {
        case .midi: return "Bluetooth MIDI piano"
        case .microphone: return "microphone"
        case .computerKeyboard: return "computer keyboard"
        }
    }

    /// The latest graded take of the open piece, kept with its report for checking the grader.
    /// The grade itself stays as it was.
    private func markTutorChatTakePlayedRight() -> String {
        guard let learner, let piece = currentPieceID,
              let take = learnerStore.history(for: learner.id).takes(for: piece).last else {
            return "There's no graded take of this piece to save yet. Play it and let it be graded first."
        }
        let folder = BookLibrary.support.appendingPathComponent("PlayedRight", isDirectory: true)
        let stamp = take.midiURL.deletingPathExtension().lastPathComponent
        let name = "\(piece.rawValue.map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }.prefix(60))-\(stamp)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (from, ext) in [(take.midiURL, "mid"), (take.reportURL, "json")] {
                let to = folder.appendingPathComponent("\(name).\(ext)")
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: from, to: to)
            }
            let label: [String: String] = ["piece": piece.rawValue, "title": tutorTitle,
                                           "input": chosenInput?.rawValue ?? "unknown",
                                           "note": "The learner says this take was played right."]
            try JSONSerialization.data(withJSONObject: label, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("\(name).label.json"), options: .atomic)
        } catch {
            return "The take couldn't be saved for checking. Your grade is unchanged."
        }
        return ran("Saved your latest take of \(tutorTitle) for checking the grader. Your grade is unchanged.")
    }

    /// Few of the expected notes were heard in the latest take: worth checking the input.
    var tutorChatFewNotesDetected: Bool {
        guard let report = tutorDisplayReport ?? self.report, report.notes.expected >= 4 else { return false }
        return Double(report.notes.correct + report.notes.wrongPitch) < Double(report.notes.expected) * 0.5
    }

    /// How the learner is playing and whether the app can hear it.
    var tutorChatDiagnostics: String {
        var lines = ["Chosen input: \(chosenInput.map(Self.tutorChatInputName) ?? "not chosen"). Microphone on: \(micOn)\(micName.isEmpty ? "" : " (\(micName))")."]
        lines.append("Bluetooth MIDI connected: " + (midiSources.isEmpty ? "none." : midiSources.joined(separator: ", ") + "."))
        if micOn {
            lines.append(String(format: "Mic level now: %.2f (0–1).", micLevel))
            if let date = Self.calibrationDate, isCalibrated {
                let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                lines.append("Mic calibrated \(days) day\(days == 1 ? "" : "s") ago.")
            } else {
                lines.append("The mic is not calibrated on this Mac.")
            }
        }
        if let report = tutorDisplayReport ?? report {
            lines.append("Latest take: \(report.notes.correct + report.notes.wrongPitch) of \(report.notes.expected) expected notes heard (\(report.notes.missed) missed, \(report.notes.extra) extra).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: C4 · Progress and planning

    /// Why a goal date can't be used, or nil when it's absent or fine (today to two years ahead).
    static func tutorChatGoalDateProblem(_ text: String?, now: Date = Date()) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let day = tutorChatParseDay(text) else { return "Give the goal's date as YYYY-MM-DD. Nothing was saved." }
        let today = Calendar.current.startOfDay(for: now)
        guard day >= today, day <= today.addingTimeInterval(2 * 366 * 86_400) else {
            return "Choose a goal date from today to two years ahead. Nothing was saved."
        }
        return nil
    }

    static func tutorChatParseDay(_ text: String) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    static func tutorChatDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Saves (or clears) today's plan for the active learner.
    func setTutorChatSessionPlan(_ plan: TutorSessionPlan?) {
        tutorChatSessionPlan = plan
        guard let learner else { return }
        try? tutorChatMemory(for: learner.id).save(plan: plan)
    }

    /// The learner ticked a step of today's plan.
    func toggleTutorChatPlanStep(_ index: Int) {
        guard var plan = tutorChatSessionPlan, plan.steps.indices.contains(index) else { return }
        plan.steps[index].done.toggle()
        setTutorChatSessionPlan(plan)
    }

    /// Printed book numbers can repeat in played order. Choose the first complete occurrence.
    private func tutorChatPlayedRange(_ printed: ClosedRange<Int>, full: MIDISequence) -> ClosedRange<Int>? {
        guard printed.count <= full.measureCount else { return nil }
        for start in 1...(full.measureCount - printed.count + 1) {
            let end = start + printed.count - 1
            if Array(start...end).map({ passage?.printedMeasure(forPlayed: $0) ?? $0 }) == Array(printed) { return start...end }
        }
        return nil
    }
}
#endif
