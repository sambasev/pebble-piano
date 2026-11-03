import Foundation
import PianoGraderCore

/// The reading course: one page per stage, a lesson then a ten-question quiz.
public enum SightReadingCourse {
    public static let unitID = "sight-reading"

    public static var unit: LessonUnit {
        let stages = SightCurriculum.levels.flatMap { level in level.stages.map { (level, $0) } }
        return LessonUnit(id: unitID, title: "Read music", pages: stages.enumerated().map { index, item in
            let (level, stage) = item
            let next = index + 1 < stages.count ? "sight-\(stages[index + 1].1.id.id)" : nil
            return LessonPage(id: "sight-\(stage.id.id)", title: "Level \(level.id) · \(stage.title)", blocks: [
                .explain(.init(text: stage.lesson, highlight: stage.keys.map { NoteName(pitch: $0) })),
                .sightReading(.init(level: level.id, stage: stage.id.stage)),
            ], unlocks: next)
        })
    }
}
