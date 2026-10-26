import Foundation
import PianoGraderCore

/// A teacher: how strict the judging is, when hints and the teacher step in, what a page needs
/// to pass, how the fix-my-mistakes drill runs, and how the messages sound.
/// Files: `Lessons/personas/<id>.json`. The built-in copies are used when a file is missing.
public struct Persona: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// One line for the teacher picker.
    public var summary: String
    public var hintAfter: Int
    public var teacherAfter: Int
    /// Stars a song (or other starred block) needs to count as passed.
    public var requiredStars: Int
    /// Play-along judging for Practise and the drill: "gentle", "standard" or "strict".
    public var practiceStrictness: String
    public var drill: DrillRules
    /// Message templates by key (see `Message`); `{bar}` and `{step}` are filled in.
    public var messages: [String: String]

    public struct DrillRules: Codable, Equatable, Sendable {
        /// Failed Perform runs on a song before the drill is offered.
        public var afterFailedPerforms: Int
        /// Open the drill by itself after the results show, instead of offering it.
        public var startsAutomatically: Bool
        /// Clean runs in a row a step needs.
        public var cleanRunsNeeded: Int
        /// Runs before a step moves on anyway; nil: until clean (the learner can still ask to move on).
        public var maxRunsPerStep: Int?
        /// Play-along speed for the slow step, as a percentage.
        public var slowTempoPercent: Double

        public init(afterFailedPerforms: Int = 2, startsAutomatically: Bool = false, cleanRunsNeeded: Int = 1,
                    maxRunsPerStep: Int? = 4, slowTempoPercent: Double = 70) {
            self.afterFailedPerforms = afterFailedPerforms
            self.startsAutomatically = startsAutomatically
            self.cleanRunsNeeded = cleanRunsNeeded
            self.maxRunsPerStep = maxRunsPerStep
            self.slowTempoPercent = slowTempoPercent
        }
    }

    public enum Message: String, CaseIterable, Sendable {
        /// Results card, Perform didn't reach the stars needed.
        case performFailed
        /// Results card, offering the drill.
        case drillOffer
        /// The drill opens.
        case drillIntro
        /// A drill run was clean but the step needs more.
        case runClean
        /// A drill run wasn't clean; going again.
        case runAgain
        /// A step is done.
        case stepDone
        /// A step ran out of runs (or the learner asked to move on).
        case movingOn
        /// All steps done: back to Perform.
        case drillDone
    }

    public var rules: EscalationRules {
        EscalationRules(hintAfter: hintAfter, teacherAfter: teacherAfter, requiredStars: requiredStars)
    }

    /// The play-along judging for Practise and the drill.
    public var playAlong: Rubric.PlayAlong {
        switch practiceStrictness {
        case "strict": return .strict
        case "standard": return .standard
        default: return .gentle
        }
    }

    /// A message with `{bar}` and `{step}` filled in. Falls back to Alex's wording.
    public func say(_ message: Message, bar: Int? = nil, step: String? = nil) -> String {
        var text = messages[message.rawValue] ?? Persona.alex.messages[message.rawValue] ?? ""
        if let bar { text = text.replacingOccurrences(of: "{bar}", with: "\(bar)") }
        if let step { text = text.replacingOccurrences(of: "{step}", with: step) }
        return text
    }

    // MARK: Built in

    public static let defaultID = "alex"

    public static let alex = Persona(
        id: "alex", name: "Alex", summary: "Relaxed: one star moves you on, and the drill is offered, never forced.",
        hintAfter: 2, teacherAfter: 3, requiredStars: 1, practiceStrictness: "gentle",
        drill: DrillRules(afterFailedPerforms: 2, startsAutomatically: false, cleanRunsNeeded: 1, maxRunsPerStep: 4),
        messages: [
            "performFailed": "Nice try! That one's tricky. Have another go, or let's fix the hard bit together.",
            "drillOffer": "Bar {bar} is the tricky bit. Want to fix it together?",
            "drillIntro": "Let's fix bar {bar}. Notes first: the music waits for you.",
            "runClean": "Lovely, that's it! Once more like that.",
            "runAgain": "Almost. Here it comes again.",
            "stepDone": "Great. Next: {step}.",
            "movingOn": "Good effort. Let's keep going: {step}.",
            "drillDone": "Bar {bar} sounds much better. Now perform the whole song.",
        ])

    public static let kriti = Persona(
        id: "kriti", name: "Kriti", summary: "Strict: two stars to move on, and two clean runs in a row in the drill.",
        hintAfter: 2, teacherAfter: 3, requiredStars: 2, practiceStrictness: "standard",
        drill: DrillRules(afterFailedPerforms: 2, startsAutomatically: true, cleanRunsNeeded: 2, maxRunsPerStep: nil),
        messages: [
            "performFailed": "Not yet. We'll fix it.",
            "drillOffer": "Bar {bar} needs work. We'll drill it now.",
            "drillIntro": "Bar {bar}. Notes first, then in time. Clean twice in a row before we move on.",
            "runClean": "Clean. Once more.",
            "runAgain": "Again.",
            "stepDone": "Good. Next: {step}.",
            "movingOn": "We'll come back to it. Next: {step}.",
            "drillDone": "Bar {bar} is clean. Now the whole song, full speed.",
        ])

    public static let builtIn: [Persona] = [alex, kriti]

    /// `<folder>/<id>.json`, else the built-in persona, else Alex.
    public static func load(_ id: String?, folder: URL?) -> Persona {
        let id = id ?? defaultID
        if let folder,
           let data = try? Data(contentsOf: folder.appendingPathComponent("\(id).json")),
           let persona = try? JSONDecoder().decode(Persona.self, from: data) {
            return persona
        }
        return builtIn.first { $0.id == id } ?? alex
    }
}
