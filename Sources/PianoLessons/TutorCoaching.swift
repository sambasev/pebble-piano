import PianoGraderCore

/// A teacher's first response, available immediately even without an AI connection.
/// Measurements stay in the grade report; this turns evidence into one actionable cue.
public enum TutorCoaching {
    public static func message(report: GradeReport, next: PracticeExercise, mastered: Bool,
                               printedMeasures: [Int], notesCompleted: Bool = false, stars: Int? = nil,
                               followingPlan: Bool = false, passedWithSlips: Bool = false) -> String {
        if mastered {
            let earned = stars.map { " That's \($0) star\($0 == 1 ? "" : "s")." } ?? ""
            if passedWithSlips {
                return "That's a pass—\(percent(report))% of the notes right and on time.\(earned) You've passed this piece. " + watchOut(report)
            }
            return "That was a good run—you kept the notes and timing together.\(earned) You've passed this piece. You can play it again to make it feel more comfortable."
        }
        let observation: String
        if passedWithSlips {
            observation = "That's a pass—\(percent(report))% of the notes right and on time, so this step is done. " + watchOut(report)
        } else if let stars, !mastered {
            observation = stars > 0
                ? "That performance earned \(stars) star\(stars == 1 ? "" : "s"). Let's polish the part that slipped."
                : "That performance didn't earn a star yet. Let's work on the part that slipped."
        } else if notesCompleted {
            observation = followingPlan ? "Good—you found every note." : "You've worked through the notes. Now let's put them together."
        } else if let mistake = MistakeExplainer.explain(report, limit: 1).first {
            observation = mistake
        } else if report.notes.extra > 0 {
            observation = "A few extra notes slipped in. Let's give each note a little more attention."
        } else if let timing = report.timing, timing.tempoDeviation > 0.15 {
            observation = "You played faster than the target tempo. Give yourself a little more time between notes."
        } else if let timing = report.timing, timing.tempoDeviation < -0.15 {
            observation = "You played below the target tempo. Let's build up to it while keeping the beat steady."
        } else if report.timing == nil {
            observation = "I couldn't judge the timing from that try yet."
        } else if !report.passed {
            observation = "The beat wasn't quite steady on that try. Let's give the rhythm some attention."
        } else {
            observation = "That was a good practice run. Let's build on it."
        }
        return observation + " " + invitation(for: next, printedMeasures: printedMeasures)
    }

    /// "Just watch out for this: …" with the run's main slips, and how to come back to them.
    static func watchOut(_ report: GradeReport) -> String {
        let slips = MistakeExplainer.explain(report, limit: 2)
        let what = slips.isEmpty ? "" : "Just watch out for \(slips.count == 1 ? "this" : "these"): " + slips.joined(separator: " ") + " "
        return what + "If you'd like to revisit them, mark the bars you got wrong and practise them."
    }

    private static func percent(_ report: GradeReport) -> Int { Int((min(1, RemediationPlanner.passScore(report)) * 100).rounded()) }

    /// After "Show me what you can do": how each phrase went, in a sentence.
    public static func placementSummary(_ grades: [Int: PhraseGrade], plan: LessonPlan) -> String {
        let parts = plan.phrases.indices.compactMap { i in grades[i].map { "\(plan.phrases[i].label): \($0.summary)" } }
        guard !parts.isEmpty else { return "" }
        if grades.values.allSatisfy({ $0 == .clean }) { return "You played every phrase cleanly. " }
        return parts.joined(separator: "; ") + ". "
    }

    /// What to do next, in a teacher's words.
    public static func invitation(for next: PracticeExercise, printedMeasures: [Int]) -> String {
        let bars = Array(Set(printedMeasures)).sorted()
        var location: String
        if bars.isEmpty {
            location = "this section"
        } else if bars.count == 1 {
            location = "bar \(bars[0])"
        } else if bars.count > 2 && bars == Array(bars[0]...bars[bars.count - 1]) {
            location = "bars \(bars[0])–\(bars[bars.count - 1])"
        } else {
            location = "bars " + bars.map(String.init).joined(separator: ", ")
        }
        if let label = next.label { location = "\(label.prefix(1).lowercased() + label.dropFirst()) (\(location))" }
        let hand = next.hand == .right ? " with your right hand" : next.hand == .left ? " with your left hand" : ""
        switch next.kind {
        case .notes:
            return "Let's work through \(location)\(hand) one note at a time. Follow the highlighted keys; the music will wait for you."
        case .slow:
            return "Let's try \(location)\(hand) again slowly. Listen to the clicks and give each note its own place in the beat."
        case .fullSpeed:
            return "Let's try \(location)\(hand) at the piece's full speed, keeping the same steady beat."
        case .context:
            return "Let's connect the tricky part to the music around it. Play \(location) together and keep the beat going across the barlines."
        case .assessment:
            return "Let's try the whole piece again. Play after the count-in and keep going through any slips; we'll look at them afterwards."
        case .listen:
            return "First, listen to the whole piece and follow the music."
        case .newNote:
            let note = next.note.map { "\($0.letter)" } ?? "the new note"
            return "Next, a new note: find \(note) on the keyboard and play it\(hand)."
        case .perform:
            return "Now perform the whole piece at full speed, after the count-in. Keep going through any slips."
        case .placement:
            return "First, show me what you can do: play the whole piece after the count-in. I'll skip the parts you already play well."
        }
    }
}
