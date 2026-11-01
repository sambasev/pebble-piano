import Foundation
import PianoGraderCore

/// A lesson plan as a page in Learn: the same steps as the tutor, made of the block types
/// Learn already plays. Listen, the new notes, each phrase note by note (hands separately when
/// the plan says so) and then in time, slowly, and the whole piece as a song challenge
/// (Listen → Learn → Practise → Perform, for stars).
public enum PieceLessonBuilder {
    /// The page, and the MIDI files its blocks name (file name → music), to write next to it.
    public struct Output: Sendable {
        public var page: LessonPage
        public var files: [String: MIDISequence]
    }

    /// `id`: the page's ID (unique among the learner's pieces). `slowPercent`: the slow steps'
    /// speed, percent of the piece's tempo.
    public static func build(plan: LessonPlan, sequence: MIDISequence, title: String, id: String,
                             slowPercent: Double = 70) -> Output {
        let count = max(1, sequence.measureCount)
        let bpm = sequence.initialTempoBPM
        let beats = max(1, sequence.timeSignature.numerator)
        var files: [String: MIDISequence] = ["whole.mid": sequence]
        var blocks: [Block] = [.listen(.init(midi: "whole.mid", prompt: "Listen to \(title) and follow the music.", tempo: bpm))]
        for n in plan.newNotes {
            blocks.append(.explain(.init(text: n.introduction, highlight: [n.note], advanceOn: n.note)))
        }
        for (i, p) in plan.phrases.enumerated() {
            let lo = max(1, min(count, p.bars.lowerBound)), hi = max(lo, min(count, p.bars.upperBound))
            let bars = lo == hi ? "bar \(lo)" : "bars \(lo)–\(hi)"
            let slice = sequence.measures(lo...hi)
            let base = "phrase\(i + 1)"
            if plan.handsSeparately && sequence.hasTwoHands {
                for (hand, name) in [(Hand.right, "right"), (Hand.left, "left")] {
                    let file = "\(base)-\(hand.rawValue).mid"
                    files[file] = slice.hand(hand)
                    blocks.append(.wait(.init(midi: file, prompt: "\(p.label), \(name) hand (\(bars)): note by note.",
                                              hand: hand, hint: p.tip)))
                }
            }
            files["\(base).mid"] = slice
            blocks.append(.wait(.init(midi: "\(base).mid", prompt: "\(p.label) (\(bars)): \(plan.handsSeparately ? "hands together, " : "")note by note.",
                                      hint: p.tip)))
            blocks.append(.timed(.init(midi: "\(base).mid", prompt: "\(p.label) (\(bars)), slowly in time.",
                                       tempo: bpm * slowPercent / 100, countInBeats: beats, hint: p.tip)))
        }
        blocks.append(.songChallenge(.init(midi: "whole.mid", title: title, practiceTempos: [slowPercent / 100, 0.85])))
        let page = LessonPage(id: id, title: title, newNotes: plan.newNotes.map(\.note), blocks: blocks,
                              hint: plan.phrases.first?.tip)
        return Output(page: page, files: files)
    }

    /// The learner's pieces as one unit: each piece's page, its MIDI paths made relative to
    /// the folder holding every piece's folder (`<folder>/<file>`). Every page is open.
    public static func unit(pages: [(folder: String, page: LessonPage)]) -> LessonUnit {
        let pages = pages.map { folder, page -> LessonPage in
            var p = page
            p.blocks = page.blocks.map { relocate($0, into: folder) }
            p.unlocks = nil
            return p
        }
        return LessonUnit(id: unitID, title: "My pieces", pages: pages, allPagesOpen: true)
    }

    public static let unitID = "my-pieces"

    static func relocate(_ block: Block, into folder: String) -> Block {
        func path(_ p: String) -> String { folder + "/" + p }
        switch block {
        case .wait(var b): b.midi = path(b.midi); return .wait(b)
        case .listen(var b): b.midi = path(b.midi); return .listen(b)
        case .timed(var b): b.midi = path(b.midi); return .timed(b)
        case .songChallenge(var b): b.midi = path(b.midi); return .songChallenge(b)
        default: return block
        }
    }
}
