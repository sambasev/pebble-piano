import Foundation

/// One possible question: an answer and what to show for it.
struct SightTemplate: Sendable {
    let answer: SightAnswer
    let prompt: String
    let score: Score
    let playPitch: Int?
    let explanation: String
}

public enum SightQuestionGenerator {
    /// `count` questions for the stage, every answer coming up before any repeats, and never
    /// the same picture twice in a row.
    public static func quiz(stage: SightStageID, seed: UInt64, count: Int = 10) -> [SightQuestion] {
        let templates = Self.templates(stage)
        guard !templates.isEmpty, count > 0 else { return [] }
        var rng = EarRandom(state: seed)
        let answers = uniqueAnswers(templates)
        var bag: [SightAnswer] = []
        var questions: [SightQuestion] = []
        for index in 0..<count {
            if bag.isEmpty {
                bag = rng.shuffled(answers)
                if bag.last?.id == questions.last?.correctAnswer.id, bag.count > 1 { bag.swapAt(0, bag.count - 1) }
            }
            let answer = bag.removeLast()
            let variants = templates.filter { $0.answer.id == answer.id }
            var template = variants[rng.index(variants.count)]
            if variants.count > 1 {
                while template.score == questions.last?.score { template = variants[rng.index(variants.count)] }
            }
            questions.append(question(template, stage: stage, answers: answers, id: "\(stage.id).\(seed).\(index)"))
        }
        return questions
    }

    /// One labeled picture per variant: the lesson's "show me" examples.
    public static func examples(stage: SightStageID) -> [SightQuestion] {
        let templates = Self.templates(stage)
        let answers = uniqueAnswers(templates)
        return templates.enumerated().map { question($1, stage: stage, answers: answers, id: "\(stage.id).example.\($0)") }
    }

    private static func question(_ t: SightTemplate, stage: SightStageID, answers: [SightAnswer], id: String) -> SightQuestion {
        SightQuestion(id: id, stage: stage, prompt: t.prompt, score: t.score, correctAnswer: t.answer,
                      choices: answers, playPitch: t.playPitch, explanation: t.explanation)
    }

    /// Answers in the order they were first written, each once; note letters in C-to-B order.
    private static func uniqueAnswers(_ templates: [SightTemplate]) -> [SightAnswer] {
        var seen = Set<String>()
        let answers = templates.map(\.answer).filter { seen.insert($0.id).inserted }
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        guard answers.allSatisfy({ letters.contains($0.id) }) else { return answers }
        return answers.sorted { letters.firstIndex(of: $0.id)! < letters.firstIndex(of: $1.id)! }
    }

    // MARK: Templates

    static func templates(_ id: SightStageID) -> [SightTemplate] {
        switch (id.level, id.stage) {
        case (1, 1):
            let line = SightAnswer(id: "line", title: "On a line"), space = SightAnswer(id: "space", title: "In a space")
            return [64, 67, 71, 74, 77].map { pitch in
                SightTemplate(answer: line, prompt: "Is this note on a line or in a space?", score: staff(.treble, .note(pitch, .whole)),
                              playPitch: nil, explanation: "The line runs through the middle of the note: it's a line note.")
            } + [65, 69, 72, 76].map { pitch in
                SightTemplate(answer: space, prompt: "Is this note on a line or in a space?", score: staff(.treble, .note(pitch, .whole)),
                              playPitch: nil, explanation: "The note fits between two lines: it's a space note.")
            }
        case (1, 2):
            return [
                SightTemplate(answer: SightAnswer(id: "treble", title: "Treble clef"), prompt: "Which clef is this?",
                              score: staff(.treble, nil), playPitch: nil,
                              explanation: "The treble (G) clef curls around the G line. It's for the higher notes."),
                SightTemplate(answer: SightAnswer(id: "bass", title: "Bass clef"), prompt: "Which clef is this?",
                              score: staff(.bass, nil), playPitch: nil,
                              explanation: "The bass (F) clef's two dots sit either side of the F line. It's for the lower notes."),
            ]
        case (1, 3):
            return [Clef.treble, .bass].flatMap { clef in
                [60, 62, 59].map { name($0, clef: clef, letterOnly: false) }
            }
        case (2, 1): return [60, 67, 72].map { name($0, clef: .treble) }
        case (2, 2): return [64, 67, 71, 74, 77].map { name($0, clef: .treble) }
        case (2, 3): return [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79].map { name($0, clef: .treble) }
        case (3, 1): return [43, 48, 53, 60].map { name($0, clef: .bass) }
        case (3, 2): return [43, 47, 50, 53, 57].map { name($0, clef: .bass) }
        case (3, 3): return [41, 43, 45, 47, 48, 50, 52, 53, 55, 57, 59, 60].map { name($0, clef: .bass) }
        case (4, 1): return [NoteValue.whole, .half, .quarter].flatMap { kind($0, rest: false) }
        case (4, 2): return [NoteValue.whole, .dottedHalf, .half, .quarter].flatMap { beats($0, rest: false) }
        case (4, 3): return [NoteValue.whole, .half, .quarter, .eighth].flatMap { kind($0, rest: false) }
        case (5, 1): return [NoteValue.whole, .half].flatMap { kind($0, rest: true) }
        case (5, 2): return [NoteValue.whole, .half, .quarter, .eighth].flatMap { kind($0, rest: true) }
        case (5, 3): return [NoteValue.whole, .half, .quarter, .eighth].flatMap { beats($0, rest: false) + beats($0, rest: true) }
        default: return []
        }
    }

    /// "What note is this?" for one pitch; answered by its letter (or "Middle C").
    private static func name(_ pitch: Int, clef: Clef, letterOnly: Bool = true) -> SightTemplate {
        let spelled = KeySignature.cMajor.spell(pitch)
        let isMiddleC = pitch == 60 && !letterOnly
        let answer = isMiddleC ? SightAnswer(id: "middleC", title: "Middle C") : SightAnswer(id: spelled.letter, title: spelled.letter)
        let step = clef.staffStep(of: spelled)
        let clefName = clef == .treble ? "treble" : "bass"
        return SightTemplate(answer: answer, prompt: "What note is this? Choose it, or play it.",
                             score: staff(clef, .note(pitch, .whole)), playPitch: pitch,
                             explanation: "\(isMiddleC ? "Middle C" : spelled.letter) (\(spelled.name)) sits \(place(step)) in the \(clefName) clef.")
    }

    /// Where a staff step is, in words: "on line 2", "in space 3", "on the ledger line below the staff".
    static func place(_ step: Int) -> String {
        switch step {
        case 0...8: return step % 2 == 0 ? "on line \(step / 2 + 1)" : "in space \(step / 2 + 1)"
        case -1: return "just below the staff"
        case 9: return "just above the staff"
        default:
            let below = step < 0
            let ledger = below ? (-step) / 2 : (step - 8) / 2
            let which = ledger == 1 ? "the ledger line" : "ledger line \(ledger)"
            let side = below ? "below the staff" : "above the staff"
            if step % 2 == 0 { return "on \(which) \(side)" }
            return "\(below ? "under" : "over") \(which) \(side)"
        }
    }

    /// "What kind of note (rest) is this?"
    private static func kind(_ value: NoteValue, rest: Bool) -> [SightTemplate] {
        let noun = rest ? "rest" : "note"
        let answer = SightAnswer(id: value.id, title: "\(value.title) \(noun)")
        return pitchesFor(value, rest: rest).map { pitch in
            SightTemplate(answer: answer, prompt: "What kind of \(noun) is this?", score: staff(.treble, symbol(value, pitch: pitch)),
                          playPitch: nil, explanation: "\(rest ? value.restLook : value.noteLook) \(value.article.capitalized) \(value.title.lowercased()) \(noun) lasts \(value.beatsText).")
        }
    }

    /// "How many beats does this note (rest) last?"
    private static func beats(_ value: NoteValue, rest: Bool) -> [SightTemplate] {
        let noun = rest ? "rest" : "note"
        let answer = SightAnswer(id: "beats.\(value.beatsText)", title: value.beatsText)
        return pitchesFor(value, rest: rest).map { pitch in
            SightTemplate(answer: answer, prompt: "How many beats does this \(noun) last?", score: staff(.treble, symbol(value, pitch: pitch)),
                          playPitch: nil, explanation: "It's \(value.article) \(value.title.lowercased()) \(noun): \(value.beatsText).")
        }
    }

    private static func pitchesFor(_ value: NoteValue, rest: Bool) -> [Int?] { rest ? [nil] : [67, 72, 64] }

    private static func symbol(_ value: NoteValue, pitch: Int?) -> Symbol {
        pitch.map { .note($0, value.type, dots: value.dots) } ?? .rest(value.type, dots: value.dots)
    }

    // MARK: Building scores

    enum Symbol { case note(Int, NoteType, dots: Int = 0), rest(NoteType, dots: Int = 0) }

    /// One staff with one symbol (or none), with no time signature.
    static func staff(_ clef: Clef, _ symbol: Symbol?) -> Score {
        var events: [ScoreEvent] = []
        var length = 16
        switch symbol {
        case .note(let pitch, let type, let dots):
            length = type.sixteenths * (dots == 1 ? 3 : 2) / 2
            events = [ScoreEvent(staff: 0, start: 0, duration: length, type: type, dots: dots,
                                 notes: [ScoreNote(midi: pitch, spelled: KeySignature.cMajor.spell(pitch))])]
        case .rest(let type, let dots):
            length = type.sixteenths * (dots == 1 ? 3 : 2) / 2
            events = [ScoreEvent(staff: 0, start: 0, duration: length, type: type, dots: dots, notes: [])]
        case nil:
            break
        }
        return Score(title: "", tempoBPM: 60, timeSignature: .common, key: .cMajor, staves: [clef],
                     measures: [ScoreMeasure(number: 1, startSixteenth: 0, length: length, events: events)])
    }
}

/// The note values the course teaches.
enum NoteValue: Sendable {
    case whole, dottedHalf, half, quarter, eighth

    var id: String {
        switch self {
        case .whole: return "whole"
        case .dottedHalf: return "dottedHalf"
        case .half: return "half"
        case .quarter: return "quarter"
        case .eighth: return "eighth"
        }
    }
    var title: String {
        switch self {
        case .whole: return "Whole"
        case .dottedHalf: return "Dotted half"
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        }
    }
    var type: NoteType {
        switch self {
        case .whole: return .whole
        case .dottedHalf, .half: return .half
        case .quarter: return .quarter
        case .eighth: return .eighth
        }
    }
    var dots: Int { self == .dottedHalf ? 1 : 0 }
    var article: String { self == .eighth ? "an" : "a" }
    var beatsText: String {
        switch self {
        case .whole: return "4 beats"
        case .dottedHalf: return "3 beats"
        case .half: return "2 beats"
        case .quarter: return "1 beat"
        case .eighth: return "½ beat"
        }
    }
    var noteLook: String {
        switch self {
        case .whole: return "Open, with no stem."
        case .dottedHalf: return "Open, with a stem and a dot."
        case .half: return "Open, with a stem."
        case .quarter: return "Filled in, with a stem."
        case .eighth: return "Filled in, with a stem and a flag."
        }
    }
    var restLook: String {
        switch self {
        case .whole: return "A block hanging down from the fourth line."
        case .dottedHalf: return "A block sitting on the middle line, with a dot."
        case .half: return "A block sitting on top of the middle line."
        case .quarter: return "A tall squiggle."
        case .eighth: return "Like a 7 with a dot on its arm."
        }
    }
}
