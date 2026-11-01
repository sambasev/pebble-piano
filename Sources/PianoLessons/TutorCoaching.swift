import PianoGraderCore

/// A teacher's first response, available immediately even without an AI connection.
/// Measurements stay in the grade report; this turns evidence into one actionable cue.
public enum TutorCoaching {
    public static func message(report: GradeReport, next: PracticeExercise, mastered: Bool,
                               printedMeasures: [Int], notesCompleted: Bool = false) -> String {
        if mastered { return "That was a good run—you kept the notes and timing together. You've passed this piece. You can play it again to make it feel more comfortable." }
        let observation: String
        if notesCompleted {
            observation = "You've worked through the notes. Now let's put them together."
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
        let bars = Array(Set(printedMeasures)).sorted()
        let location = bars.count == 1 ? "bar \(bars[0])" : bars.isEmpty ? "this section" : "bars \(bars.map(String.init).joined(separator: ", "))"
        let invitation: String
        switch next.kind {
        case .notes:
            invitation = "Let's work through \(location) one note at a time. Follow the highlighted keys; the music will wait for you."
        case .slow:
            invitation = "Let's try \(location) again slowly. Listen to the clicks and give each note its own place in the beat."
        case .fullSpeed:
            invitation = "Let's try \(location) at the piece's full speed, keeping the same steady beat."
        case .context:
            invitation = "Let's connect the tricky part to the music around it. Play \(location) together and keep the beat going across the barlines."
        case .assessment:
            invitation = "Let's try the whole piece again. Play after the count-in and keep going through any slips; we'll look at them afterwards."
        }
        return observation + " " + invitation
    }
}
