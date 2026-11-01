import Foundation
import PianoGraderCore

public enum EarLessonCourse {
    public static var unit: LessonUnit {
        let stages = EarCurriculum.levels.flatMap { level in level.stages.map { (level, $0) } }
        return LessonUnit(id: "ear-training", title: "Train your ear", pages: stages.enumerated().map { index, item in
            let (level, stage) = item
            let next = index + 1 < stages.count ? "ear-\(stages[index + 1].1.id.id)" : nil
            return LessonPage(id: "ear-\(stage.id.id)", title: "Level \(level.id) · \(stage.title)", blocks: [
                .explain(.init(text: stage.detail + " Listen, use the reference, and choose the answer. Aim for 8 out of 10.")),
                .earTraining(.init(level: level.id, stage: stage.id.stage, questions: 10))
            ], unlocks: next)
        })
    }
}

/// How an ear-training step introduces itself. On a piano page it's an ear check on the note
/// the page just taught ("Ear check: can you hear E?"), so it reads as part of that lesson; on
/// the ear-training course's own pages (which teach no new notes) it's the general prompt.
public enum EarCheckWording {
    /// The step's heading.
    public static func eyebrow(newNotes: [NoteName]) -> String {
        guard !newNotes.isEmpty else { return "Train your ear" }
        return "Ear check: can you hear \(list(letters(newNotes.map(\.pitch)), joiner: "or"))?"
    }

    /// The step's instruction. `quizNotes` are the block's pitch classes (0 = C); without
    /// them, the page's new notes.
    public static func prompt(newNotes: [NoteName], quizNotes: [Int]?) -> String {
        guard !newNotes.isEmpty else { return "Listen, then choose what you hear." }
        let notes = quizNotes.map { $0.sorted().map { 60 + $0 } } ?? newNotes.map(\.pitch)
        let names = letters(notes)
        let them = names.count == 1 ? "it" : "them"
        return "You just played \(list(names, joiner: "and")). Now find \(them) by ear."
    }

    /// Note letters without octaves, each once, in order.
    private static func letters(_ pitches: [Int]) -> [String] {
        var seen = Set<String>()
        return pitches.map { NoteName(pitch: $0).letter }.filter { seen.insert($0).inserted }
    }

    /// "C", "C and D", "C, D and E".
    private static func list(_ items: [String], joiner: String) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(joiner) " + items.last!
    }
}
