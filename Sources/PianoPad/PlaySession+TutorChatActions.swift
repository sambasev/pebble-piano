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
        stopTutorChat()
    }

    func tutorChatDidGrade() {
        guard canChatWithTutor, let report = tutorDisplayReport else { return }
        let scope = tutorAttempt.map { "\($0.title), printed bars \(tutorPrinted($0))" } ?? "current passage"
        let evidence = "\(tutorTitle), \(scope), \(mode.rawValue), \(Int(tempoPercent))% speed:\n" + Self.tutorChatGradeText(report)
        tutorChatRecentGrades = Array((tutorChatRecentGrades + [evidence]).suffix(3))
        guard tutorChatCoaching, !lastTake.isEmpty, !advanceTutorChatPlan() else { return }
        tutorChatObserve("Take graded · \(tutorTitle) · \(Int(report.notes.score * 100))% notes",
                         question: "The grader has finished a real take. Use the latest grader evidence and musical goal to explain what improved, identify one concrete issue, and select the next practice action. Do not claim mastery from wait mode or a slowed run.")
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

    /// Only these bounded player operations can be requested by model output.
    @discardableResult
    func applyTutorChatAction(_ action: TutorChatAction) -> String {
        tutorChatActionRan = false
        guard canChatWithTutor else { return "Tutor actions are available only for the active adult learner." }
        // Never replace an ungraded performance or cut off a demonstration with an old decision.
        if phase == .recording && ![.gradeTake, .stop, .setGoal, .setTempo, .highlight].contains(action.kind) {
            return "A take is still recording. Finish it with Grade, or ask me to grade it, before changing the exercise."
        }
        if isAuditioning && ![.stop, .setGoal, .highlight].contains(action.kind) {
            return "The demonstration is still playing. Let it finish, or stop it before changing exercises."
        }
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
            guard let goal = TutorChat.clean(action.goal ?? "") else { return "No musical goal was provided." }
            learnerSettings.tutorGoal = String(goal.prefix(500))
            saveLearnerSettings()
            return ran("Goal saved: \(learnerSettings.tutorGoal!).")

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
            let hand: Hand? = action.hand == .both ? nil : action.hand
            if hand != nil, !full.hasTwoHands { return "This MIDI file has no separate hand tracks. I can practise the passage with all its notes instead." }
            if let hand, full.measures(played).hand(hand).notes.isEmpty { return "The selected passage has no notes for that hand." }
            let kind: PracticeExercise.Kind = action.kind == .listenPassage ? .listen : action.mode == .timed ? .slow : .notes
            guard startTutorChatPractice(PracticeExercise(kind: kind, measures: played, tempoPercent: speed, hand: hand, label: "Your practice passage"),
                                         focus: "Practise printed bars \(start)–\(end), hand \(hand?.rawValue ?? "LR"), toward the learner's goal. Keep this passage until grading supports moving on.")
            else { return "This practice passage could not be started." }
            saveChatGoal(from: action)
            let mode = action.kind == .listenPassage ? "demonstration" : action.mode == .timed ? "in time" : "note by note"
            return ran("\(tutorChatAwaitingStart ? "Prepared" : "Started") bars \(start)–\(end), \(hand?.rawValue ?? "both hands"), \(Int(speed))%, \(mode). "
                + (tutorChatAwaitingStart ? "Press Start practice when you're ready." : "Play when you're ready; I'll review the graded take."))

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

    private func saveChatGoal(from action: TutorChatAction) {
        guard let goal = TutorChat.clean(action.goal ?? "") else { return }
        learnerSettings.tutorGoal = String(goal.prefix(500))
        saveLearnerSettings()
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
