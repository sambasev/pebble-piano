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
