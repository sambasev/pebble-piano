#if os(macOS)
import AppKit
import SwiftUI
import PianoGraderCore
import PianoLessons
import PianoPadState

extension PlaySession {
    var tutorChatGoal: String {
        learnerSettings.tutorGoal ?? GoalSongs.song(learnerSettings.goalSong).map { "Learn to play \($0.title)." } ?? ""
    }

    /// What the learner is looking at, so a question asked from any tab reads in context.
    static func tutorChatSectionMeaning(_ tab: AppTab) -> String {
        switch tab {
        case .learn: return "the guided course: unit map, lesson pages and ear training"
        case .practice: return "the open piece's score and player, with the piece tutor"
        case .musicLibrary: return "browsing the music library of public-domain pieces; the player state below is the last piece opened in Practice"
        case .books: return "reading the learner's books and the pieces read from them; the player state below is the last piece opened in Practice"
        case .backingTracks: return "linking backing tracks to pieces; the player state below is the last piece opened in Practice"
        }
    }

    /// The app's own state and musical data, not a capture of the user's desktop.
    func addTutorChatEvidence(to context: inout TutorChatContext, question: String) {
        guard canAskTutor else { return }
        context.goal = tutorChatGoal.isEmpty ? "Not set; ask what the learner wants to achieve when relevant." : tutorChatGoal
        if !tutorChatGoal.isEmpty, learnerSettings.tutorGoal != nil, let date = learnerSettings.tutorGoalDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0
            context.goal += " Target date: \(Self.tutorChatDay(date)) (\(days) days from today)."
        }
        context.screen = "Section: \(tab.rawValue) (\(Self.tutorChatSectionMeaning(tab))). Player: \(phase). Mode: \(mode.rawValue). Speed: \(Int(tempoPercent))%. "
            + "Notes recorded in ongoing take: \(noteCount). Guide: \(guideProgress.done)/\(guideProgress.total). "
            + "Listening: \(isAuditioning). Coaching after takes: \(tutorChatCoaching). "
            + "Marked printed bars: \(markedBars.sorted())."
        context.screen += " Current coaching focus: \(tutorChatFocus)."
        context.screen += " Awaiting learner's Start practice: \(tutorChatAwaitingStart). Count-in: \(playAlongState == .countIn). A recording clock alone does not mean the learner has played."
        context.screen += " Keys expected now: \(expected.sorted().map(PitchName.of)); held: \(held.sorted().map(PitchName.of)); wrong held keys: \(wrong.sorted().map(PitchName.of))."
        if let q = tutorPlayhead { context.screen += " Playhead: \(q) quarter notes from the piece's start." }
        if let plan = tutor?.plan {
            context.lesson += "\nLesson plan: " + plan.phrases.prefix(32).map {
                "\($0.label), played bars \($0.bars.lowerBound)–\($0.bars.upperBound)\($0.tip.map { ": " + $0 } ?? "")"
            }.joined(separator: "; ")
            context.lesson += ". Hands separately: \(plan.handsSeparately). New notes: \(plan.newNotes.map { $0.note.name })."
        }
        if let e = tutorAttempt ?? tutor?.exercise {
            context.screen += " Current exercise: \(e.title), printed bars \(tutorPrinted(e)), \(Int(e.tempoPercent))%, hand \(e.hand?.rawValue ?? "LR")."
        }
        if let next = tutor?.exercise {
            context.screen += " Deterministic next step: \(next.title), printed bars \(tutorPrinted(next)), \(Int(next.tempoPercent))%."
        }
        if let page = lessonRunner.page {
            context.screen += " Learn page: \(page.title), ID \(page.id), block \(lessonRunner.shownIndex + 1)/\(page.blocks.count)."
            if let block = lessonRunner.shownBlock,
               let data = try? JSONEncoder().encode(block), let text = String(data: data, encoding: .utf8) {
                context.screen += " Block content (data): " + text.prefix(2000)
            }
        }
        let full = tutorFullReference ?? reference
        if let full, !full.notes.isEmpty {
            let displayed = score ?? Transcriber().transcribe(full, title: tutorTitle)
            let measures = tutorChatMeasures(in: displayed, question: question)
            context.score = tutorChatScoreText(displayed, measures: measures)
            if score != nil { context.scoreImage = tutorChatScoreImage(displayed, measures: measures) }
        } else {
            context.score = "No playable score is loaded for this block."
        }
        context.learner = "Level: \(learner?.level?.rawValue ?? "not specified"). " + learnerSkills().summary
        if let learner {
            let history = learnerStore.history(for: learner.id)
            let unit = Self.unitOne?.unit
            let progress = history.lessonProgress()
            let lessons = progress.sorted { $0.value.lastPlayed > $1.value.lastPlayed }.prefix(12).map { id, p in
                let title = unit.flatMap { u in u.pages.first(where: { id == .lessonPage(unit: u.id, page: $0.id) })?.title } ?? id.rawValue
                return "\(title): block \(p.currentBlock + 1), completed \(p.completions) times, best stars \(p.bestStars.map(String.init) ?? "none"), flagged blocks \(p.flaggedBlocks)."
            }
            let sessions = history.sessions().suffix(5).map {
                "\(Self.chatDate($0.ended)): \($0.kind.rawValue), \($0.minutes) min, pages \($0.pages), completed \($0.completedPages), new notes \($0.notesLearned), takes \($0.takes), stars \($0.stars)."
            }
            context.history = (lessons + sessions).joined(separator: "\n")
            context.progress = tutorChatProgress(history)
            context.trends = tutorChatTrends(history)
            let saved = history.allTakes().suffix(5).compactMap { take -> String? in
                guard let data = try? Data(contentsOf: take.reportURL),
                      let report = try? JSONDecoder().decode(GradeReport.self, from: data) else { return nil }
                let title = learnerSettings.recentPieces.first(where: { $0.id == take.piece })?.title ?? String(take.piece.rawValue.prefix(100))
                let metadataURL = take.reportURL.deletingPathExtension().appendingPathExtension("tutor.json")
                let metadata = (try? Data(contentsOf: metadataURL)).flatMap { try? JSONDecoder().decode(TutorAttemptContext.self, from: $0) }
                let scope = metadata.map { " Printed bars \($0.printedMeasures), \($0.mode), \(Int($0.actualTempoPercent))% speed, hand \($0.exercise.hand?.rawValue ?? "LR"). Report measure numbers below are local to that excerpt." } ?? ""
                return "Saved take \(Self.chatDate(take.date)), piece \(title).\(scope)\n" + Self.tutorChatGradeText(report)
            }
            context.grades = saved.joined(separator: "\n\n")
            if let unit {
                let done = history.completedPages(unit: unit.id)
                context.availableLessons = unit.pages.filter { unit.isUnlocked($0.id, completed: done) }.map {
                    "\($0.id): \($0.title), new notes \($0.newNotes.map(\.name).joined(separator: ", ")), completed \(done.contains($0.id))."
                }.joined(separator: "\n")
            }
            // C3: the courses startEarTraining and startSightReading open.
            let ear = EarCurriculum.levels.map(\.id), sight = SightCurriculum.levels.map(\.id)
            context.availableLessons += (context.availableLessons.isEmpty ? "" : "\n")
                + "Courses: ear training levels \(ear.min() ?? 1)–\(ear.max() ?? 1) (startEarTraining), sight reading levels \(sight.min() ?? 1)–\(sight.max() ?? 1) (startSightReading)."
        }
        if let report = tutorDisplayReport {
            context.grades += "\n\nCurrent take, \(tutorTitle), printed measure numbers, \(mode.rawValue), \(Int(tempoPercent))% speed:\n" + Self.tutorChatGradeText(report)
        }
        context.grades += tutorChatRecentGrades.isEmpty ? "" : "\n\nRecent coaching takes:\n" + tutorChatRecentGrades.joined(separator: "\n\n")
        if context.grades.isEmpty { context.grades = "No graded takes yet. The ongoing recording has not been graded." }
        context.actionResults = tutorChatActionResults.joined(separator: "\n")
    }

    private static func chatDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    // MARK: C4 · Progress and trends

    /// This week against last, pieces under way, the coach's next lesson and today's plan.
    func tutorChatProgress(_ history: LearnerHistory, now: Date = Date()) -> String {
        let sessions = history.sessions()
        let lastWeek = now.addingTimeInterval(-7 * 86_400)
        var lines = ["This week: \(WeeklyStreak.minutesThisWeek(sessions, now: now)) min on \(WeeklyStreak.daysThisWeek(sessions, now: now)) days. "
            + "Last week: \(WeeklyStreak.minutesThisWeek(sessions, now: lastWeek)) min on \(WeeklyStreak.daysThisWeek(sessions, now: lastWeek)) days."]
        let underway = history.progress().filter { !$0.value.isCompleted && !$0.key.rawValue.hasPrefix("lesson:") }
            .sorted { $0.value.lastPlayed > $1.value.lastPlayed }.prefix(5)
        if !underway.isEmpty {
            lines.append("Pieces under way: " + underway.map { id, p in
                let title = learnerSettings.recentPieces.first(where: { $0.id == id })?.title ?? String(id.rawValue.prefix(60))
                return "\(title) (\(p.attempts) takes, best \(Int(p.bestScore * 100))%, last played \(Self.tutorChatDay(p.lastPlayed)))"
            }.joined(separator: "; ") + ".")
        }
        if let unit = Self.unitOne?.unit {
            let states = history.lessonProgress().reduce(into: [String: CoachPageState]()) { states, entry in
                guard let page = unit.pages.first(where: { entry.key == .lessonPage(unit: unit.id, page: $0.id) }) else { return }
                let p = entry.value
                states[page.id] = CoachPageState(completed: p.isCompleted, inProgress: p.currentBlock > 0,
                                                 bestStars: p.bestStars, flagged: !p.flaggedBlocks.isEmpty)
            }
            if let next = Coach.nextPage(in: unit, states: states) { lines.append("Coach's next lesson: \(next.id): \(next.title).") }
        }
        if let plan = tutorChatSessionPlan { lines.append(plan.prompt) }
        return lines.joined(separator: "\n")
    }

    /// The open piece's saved takes over time, with drill bars mapped to printed numbers.
    func tutorChatTrends(_ history: LearnerHistory) -> String {
        guard let piece = currentPieceID else { return "" }
        let pieceBPM = (tutorFullReference ?? reference)?.initialTempoBPM
        let takes = history.takes(for: piece).suffix(MistakeTrends.takeLimit).compactMap { take -> TrendTake? in
            guard let data = try? Data(contentsOf: take.reportURL),
                  let report = try? JSONDecoder().decode(GradeReport.self, from: data) else { return nil }
            let metadataURL = take.reportURL.deletingPathExtension().appendingPathExtension("tutor.json")
            let metadata = (try? Data(contentsOf: metadataURL)).flatMap { try? JSONDecoder().decode(TutorAttemptContext.self, from: $0) }
            // A take outside the tutor: its speed is its target tempo against the piece's.
            let speed = metadata?.actualTempoPercent
                ?? report.timing.flatMap { t in pieceBPM.map { t.targetBPM / max(1, $0) * 100 } }
            return TrendTake(date: take.date, report: report, printedMeasures: metadata?.printedMeasures,
                             tempoPercent: speed, noteByNote: metadata?.exercise.kind == .notes || report.timing == nil)
        }
        return MistakeTrends(takes).summary(title: tutorTitle)
    }

    static func tutorChatGradeText(_ report: GradeReport) -> String {
        var text = "Passed: \(report.passed). Notes correct \(report.notes.correct)/\(report.notes.expected), wrong \(report.notes.wrongPitch), missed \(report.notes.missed), extra \(report.notes.extra), score \(Int(report.notes.score * 100))%."
        if let t = report.timing {
            text += String(format: " Tempo %.1f BPM (target %.1f); mean rhythm error %.3f; steadiness CV %.3f.", t.fittedBPM, t.targetBPM, t.meanIOIError, t.steadinessCV)
        } else { text += " Timing not assessed; this is not evidence of playing in time." }
        text += "\n" + report.levels.map { String($0.detail.prefix(200)) }.joined(separator: "; ")
        text += "\n" + report.flags.prefix(12).map { "\($0.position.label): \($0.message)" }.joined(separator: "; ")
        text += "\n" + report.results.filter { $0.kind != .correct }.prefix(16).map {
            "\($0.position.label) \($0.kind.rawValue), expected \($0.expectedPitch.map(PitchName.of) ?? "none"), played \($0.playedPitch.map(PitchName.of) ?? "none")"
        }.joined(separator: "; ")
        return text
    }

    private func tutorChatMeasures(in score: Score, question: String) -> [ScoreMeasure] {
        if score.measures.count <= 16 { return score.measures }
        // Asked-for bars come first, so a late passage isn't lost to a prompt-size cap.
        let requested = question.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.prefix(8)
        var numbers = Array(requested) + (tutorAttempt.map { tutorPrinted($0) } ?? []) + mistakeMeasures.sorted()
        if let q = tutorPlayhead, let index = score.measureIndex(atQuarter: q) { numbers.append(score.measures[index].number) }
        numbers += Array(score.measures.prefix(4).map(\.number))
        var seen = Set<Int>()
        return numbers.flatMap { n in score.measures.filter { abs($0.number - n) <= 1 } }
            .filter { seen.insert($0.number).inserted }.prefix(16).sorted { $0.number < $1.number }
    }

    private func tutorChatScoreText(_ score: Score, measures: [ScoreMeasure]) -> String {
        let full = tutorFullReference ?? reference
        var text = "\(score.title). \(score.measures.count) bars. \(score.timeSignature.numerator)/\(score.timeSignature.denominator), \(score.tempoBPM) BPM; key signature \(score.key.fifths) fifths, minor \(score.key.isMinor). Staves: \(score.staves.map(\.rawValue)).\n"
        text += "Each event gives beat (denominator beats from 1), duration in quarter notes, pitches/rest and staff. Fingering is suggested by the app unless the source book supplies it.\n"
        for m in measures {
            let printed = passage?.printedMeasure(forPlayed: m.number) ?? m.number
            var line = "Bar \(printed) (played bar \(m.number)):\n"
            for e in m.events {
                let beat = 1 + Double(e.start) / 4 / score.timeSignature.quartersPerBeat
                let q = Double(m.startSixteenth + e.start) / 4
                let notes = e.notes.map { n -> String in
                    let finger = fingeringNotes.first { $0.pitch == n.midi && abs($0.quarter - q) < 0.02 }
                    return n.spelled.name + (finger.map { "[\($0.hand.rawValue) finger \($0.finger)]" } ?? "") + (n.tieStop ? " tied from previous" : "")
                }.joined(separator: "+")
                line += " staff \(e.staff + 1), beat \(String(format: "%g", beat)), duration \(Double(e.duration) / 4)q: \(e.isRest ? "rest" : notes);\n"
            }
            if text.count + line.count > 24000 { text += "Remaining score excerpt omitted for length.\n"; break }
            text += line
        }
        if let full { text += "Playable bar count: \(full.measureCount). Separate hand tracks available: \(full.hasTwoHands). " }
        if measures.count < score.measures.count { text += "Excerpt only; other bars are omitted, not empty." }
        return text
    }

    private func tutorChatScoreImage(_ score: Score, measures: [ScoreMeasure]) -> Data? {
        MainActor.assumeIsolated {
            var excerpt = score
            excerpt.measures = Array(measures.prefix(8))
            let layout = ScoreLayout(score: excerpt, width: 1000)
            guard layout.height < 2200 else { return nil }
            let drawing = ScoreRenderer(layout: layout).renderScore(mistakeMeasures: mistakeMeasures, cleanTints: false)
            let content = Canvas { graphics, _ in
                DrawingPainter.paint(drawing.items, paper: .light, in: &graphics)
            }.frame(width: 1000, height: layout.height).background(Color.white)
            let renderer = ImageRenderer(content: content)
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }
    }
}
#endif
