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
        guard tutorChatCoaching, !lastTake.isEmpty else { return }
        tutorChatObserve("Take graded · \(tutorTitle) · \(Int(report.notes.score * 100))% notes",
                         question: "The grader has finished a real take. Use the latest grader evidence and musical goal to explain what improved, identify one concrete issue, and select the next practice action. Do not claim mastery from wait mode or a slowed run.")
    }

    func tutorChatDidListen() {
        guard canChatWithTutor, tutorChatCoaching, tutor != nil else { return }
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
        guard canChatWithTutor else { return "Tutor actions are available only for the active adult learner." }
        // Never replace an ungraded performance or cut off a demonstration with an old decision.
        if phase == .recording && ![.gradeTake, .stop, .setGoal, .setTempo].contains(action.kind) {
            return "A take is still recording. Finish it with Grade, or ask me to grade it, before changing the exercise."
        }
        if isAuditioning && ![.stop, .setGoal].contains(action.kind) {
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
            return "Set this passage to \(Int(speed))% speed. Your take has not been graded."

        case .setGoal:
            guard let goal = TutorChat.clean(action.goal ?? "") else { return "No musical goal was provided." }
            learnerSettings.tutorGoal = String(goal.prefix(500))
            saveLearnerSettings()
            return "Goal saved: \(learnerSettings.tutorGoal!)."

        case .gradeTake:
            guard phase == .recording, noteCount > 0, playAlongState != .countIn else {
                return "No played take is ready to grade. Start practice and play the passage first."
            }
            tutorChatOffersGrade = true
            tutorChatCoaching = true
            return "Press Grade take when you've finished playing. Changing settings does not grade your take."

        case .stop:
            pauseTutorChatCoaching()
            stopListening()
            if phase == .recording && noteCount > 0 {
                stopPlayAlong(discard: false)
                tutorChatOffersGrade = true
                return "Coaching paused. Your ungraded take is kept; press Grade take when you're finished."
            }
            endTutoring()
            return "Coaching paused. No take was graded."

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
            return "Opened \(page.title). I'll follow the graded attempts in this lesson. Open Tutor in the header to keep chatting."

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
            return tutorPlanning ? "Planning a lesson for \(tutorTitle). I'll prepare its first step when the plan is ready."
                : tutorChatAwaitingStart ? "The next step is ready. Press Start practice when you're ready."
                : "Started the next step for \(tutorTitle)."

        case .continueLesson:
            guard !isInLesson, tutor != nil, !tutorPlanning else { return "No piece-tutor step is ready. Start a lesson first, or continue the open Learn lesson with its controls." }
            tutorChatCoaching = true
            startTutorExercise(waitForReady: true)
            return tutorChatAwaitingStart ? "The next step is ready. Press Start practice when you're ready for the count-in."
                : "Started \(tutorAttempt?.title ?? "the demonstration") for \(tutorTitle)."

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
            let exercise = PracticeExercise(kind: kind, measures: played, tempoPercent: speed, hand: hand, label: "Your practice passage")
            if tutor == nil { beginTutoring() }
            guard var engine = tutor, engine.selectExercise(exercise) else { return "This practice passage could not be started." }
            tutorLeaveAttempt()
            tutor = engine
            tutorPlanning = false
            tutorPlanTask?.cancel(); tutorPlanID = UUID()
            saveChatGoal(from: action)
            tutorChatCoaching = true
            tutorChatFocus = "Practise printed bars \(start)–\(end), hand \(hand?.rawValue ?? "LR"), toward the learner's goal. Keep this passage until grading supports moving on."
            startTutorExercise(waitForReady: true)
            let mode = action.kind == .listenPassage ? "demonstration" : action.mode == .timed ? "in time" : "note by note"
            return "\(tutorChatAwaitingStart ? "Prepared" : "Started") bars \(start)–\(end), \(hand?.rawValue ?? "both hands"), \(Int(speed))%, \(mode). "
                + (tutorChatAwaitingStart ? "Press Start practice when you're ready." : "Play when you're ready; I'll review the graded take.")
        }
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
