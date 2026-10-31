import Foundation

/// SplitMix64 keeps question construction reproducible without depending on system randomness.
struct EarRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }
    mutating func shuffled<T>(_ input: [T]) -> [T] {
        var result = input
        if result.count > 1 {
            for i in stride(from: result.count - 1, through: 1, by: -1) {
                result.swapAt(i, index(i + 1))
            }
        }
        return result
    }
}

public enum EarQuestionGenerator {
    public static func quiz(stage: EarStageID, seed: UInt64, count: Int = 10, notes: [Int]? = nil) -> [EarQuestion] {
        let templates = EarCurriculum.templates(stage).filter { template in
            notes.map { $0.contains(Int(template.answer.id.replacingOccurrences(of: "note.", with: "")) ?? -1) } ?? true
        }
        if notes != nil && Set(templates.map(\.answer.id)).count < 2 { return [] }
        guard !templates.isEmpty, count > 0 else { return [] }
        var rng = EarRandom(state: seed)
        let answers = uniqueAnswers(templates)
        var bag: [EarAnswer] = []
        var questions: [EarQuestion] = []
        for index in 0..<count {
            if bag.isEmpty {
                bag = rng.shuffled(answers)
                // Fixed-octave note pools cannot vary a repeated category's stimulus.
                if bag.last?.id == questions.last?.correctAnswer.id, bag.count > 1 {
                    bag.swapAt(0, bag.count - 1)
                }
            }
            let answer = bag.removeLast()
            let variants = templates.filter { $0.answer.id == answer.id }
            var question: EarQuestion
            repeat {
                let template = variants[rng.index(variants.count)]
                question = makeQuestion(template, stage: stage, templates: templates, rng: &rng,
                                        id: "\(stage.id).\(seed).\(index)", learning: false)
            } while question.stimulus == questions.last?.stimulus
            questions.append(question)
        }
        return questions
    }

    /// Includes every template variant (directions and chord qualities as well as answer categories).
    public static func examples(stage: EarStageID) -> [EarQuestion] {
        let templates = EarCurriculum.templates(stage)
        var rng = EarRandom(state: 0)
        return templates.enumerated().map { index, template in
            makeQuestion(template, stage: stage, templates: templates, rng: &rng,
                         id: "learn.\(stage.id).\(index)", learning: true)
        }
    }

    private static func uniqueAnswers(_ templates: [EarTemplate]) -> [EarAnswer] {
        var seen = Set<String>()
        return templates.compactMap { seen.insert($0.answer.id).inserted ? $0.answer : nil }
    }

    private static func makeQuestion(_ template: EarTemplate, stage: EarStageID, templates: [EarTemplate],
                                     rng: inout EarRandom, id: String, learning: Bool) -> EarQuestion {
        let isNote = stage.level <= 2
        let root = isNote || learning ? 0 : rng.index(12)
        let base = isNote ? (stage.level == 2 && stage.stage == 3 && !learning ? 48 + 12 * rng.index(3) : 60)
                         : (learning ? 48 : 48 + 12 * rng.index(2)) + root
        let rootName = EarCurriculum.pitchName(base)
        var voices = template.voices
        if stage.level == 7 && stage.stage == 3 {
            // Keep the tonic in the reference. Move individual chord tones to form open/inverted voicings.
            let inversion = learning ? 1 : rng.index(voices[0].count)
            voices[0] = Array(voices[0].dropFirst(inversion)) + voices[0].prefix(inversion).map { $0 + 24 }
            voices[0].sort()
        }
        if stage.level == 8 && stage.stage == 1 && !learning && rng.index(2) == 1 {
            // A second register for the upper color tones; retain the defining third and seventh.
            voices[0][2] += 12
            voices[0][3] += 12
        }
        var notes: [NoteEvent] = []
        func add(_ offsets: [Int], at onset: Double, duration: Double, velocity: Int = 76) {
            notes += offsets.map { NoteEvent(pitch: base + $0, onset: onset, offset: onset + duration, velocity: velocity) }
        }
        let prompt: String
        let context: String
        switch template.pattern {
        case .note:
            prompt = "Which note do you hear?"
            context = "Name the pitch class. The C reference is always available."
            add(voices[0], at: 0, duration: 0.85)
        case .chord:
            prompt = stage.level == 4 && stage.stage != 2 ? "Which inversion do you hear?" : "Which chord quality do you hear?"
            context = "Root: \(rootName)" + (template.subject.isEmpty ? " · compare the chord colors" : " · \(template.subject)")
            add(voices[0], at: 0, duration: 1.5)
        case .ascending, .descending, .harmonic:
            prompt = "Which interval do you hear?"
            let style = template.pattern == .ascending ? "Ascending" : template.pattern == .descending ? "Descending" : "Simultaneous"
            context = "\(style) · identify the distance between pitches"
            if template.pattern == .harmonic { add([0, voices[1][0]], at: 0, duration: 1.2) }
            else {
                let ordered = template.pattern == .ascending ? voices : voices.reversed().map { $0 }
                for (i, voice) in ordered.enumerated() { add(voice, at: Double(i) * 0.85, duration: 0.65) }
            }
        case .melody:
            prompt = "Which scale-degree pattern do you hear?"
            context = "Key: \(rootName) major · degree 1 is the tonic"
            for (i, voice) in voices.enumerated() { add(voice, at: Double(i) * 2 / 3, duration: 0.52) }
        case .progression:
            prompt = stage.level == 8 && stage.stage == 3 ? "Where does the second ii–V–I arrive?" : "Which progression do you hear?"
            // Do not reveal the answer by displaying major/minor in the mixed ii–V quiz.
            context = "\(stage.level == 8 && stage.stage == 3 ? "Starting tonic" : "Tonic"): \(rootName) · follow the bass and resolution"
            for (i, voice) in voices.enumerated() { add(voice, at: Double(i) * 4 / 3, duration: 1.15) }
        case .rootless:
            prompt = "Which dominant color do you hear?"
            context = "Root: \(rootName) · bass cue, then rootless voicing"
            add([-12], at: 0, duration: 0.65, velocity: 84)
            add(voices[0], at: 0.95, duration: 1.6)
        }
        let reference: [NoteEvent]
        let referenceLabel: String
        if isNote {
            referenceLabel = "C4 reference"
            reference = [NoteEvent(pitch: 60, onset: 0, offset: 0.85)]
        } else if template.pattern == .melody || template.pattern == .progression {
            referenceLabel = "\(rootName) tonic reference"
            // A neutral fifth provides context without revealing major vs minor in Level 6.
            reference = [0, 7, 12].map { NoteEvent(pitch: base + $0, onset: 0, offset: 1.1) }
        } else {
            referenceLabel = "\(rootName) root reference"
            reference = [NoteEvent(pitch: base, onset: 0, offset: 0.85)]
        }
        let allAnswers = uniqueAnswers(templates)
        let choices: [EarAnswer]
        if isNote { choices = allAnswers }
        else {
            // Melody distractors have the same length, so rhythm/length cannot reveal the answer.
            let candidates = template.pattern == .melody
                ? uniqueAnswers(templates.filter { $0.voices.count == template.voices.count }) : allAnswers
            let others = rng.shuffled(candidates.filter { $0.id != template.answer.id })
            choices = rng.shuffled([template.answer] + Array(others.prefix(3)))
        }
        let pitches = notes.sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
        let spelling = pitches.map { note in
            EarCurriculum.pitchName(note.pitch).components(separatedBy: " / ")
                .map { $0 + String(note.pitch / 12 - 1) }.joined(separator: " / ")
        }.joined(separator: " · ")
        let label = template.answer.title + (template.subject.isEmpty ? "" : " · \(template.subject)")
        return EarQuestion(id: id, stage: stage, prompt: prompt, context: context,
                           correctAnswer: template.answer, choices: choices, stimulus: pitches,
                           reference: reference, referenceLabel: referenceLabel, solution: pitches,
                           explanation: template.explanation, solutionLabel: "\(label)\n\(spelling)")
    }
}
