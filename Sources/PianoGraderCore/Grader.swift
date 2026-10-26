import Foundation

/// Grades a performed take against a reference passage.
///
/// Pipeline: group chords → align (Needleman–Wunsch) → classify each note →
/// fit tempo over matched events → rhythm error per interval → apply the rubric.
public struct Grader: Sendable {
    public var rubric: Rubric

    public init(rubric: Rubric = .beginner) {
        self.rubric = rubric
    }

    public func grade(referenceURL: URL, takeURL: URL) throws -> GradeReport {
        try grade(reference: MIDIFile.read(url: referenceURL), take: MIDIFile.read(url: takeURL))
    }

    public func grade(reference: MIDISequence, take: MIDISequence) -> GradeReport {
        let window = rubric.chordWindowMs / 1000.0
        let ts = reference.timeSignature
        let refChords = ChordGrouping.group(reference.notes, window: window)
        let perfChords = ChordGrouping.group(take.notes, window: window)
        let steps = Aligner.align(reference: refChords, performance: perfChords)

        // A step "matches" if the paired events share at least one pitch.
        func isMatch(_ step: AlignmentStep) -> Bool {
            if case let .pair(r, p) = step {
                return !refChords[r].pitches.isDisjoint(with: perfChords[p].pitches)
            }
            return false
        }
        let firstMatch = steps.firstIndex(where: isMatch)
        let lastMatch = steps.lastIndex(where: isMatch)

        var results: [NoteResult] = []
        var flags: [GradeFlag] = []
        var ignoredLeading = 0, ignoredTrailing = 0
        var lastRefBeats = refChords.first?.onsetBeats ?? 0
        var anchors: [Anchor] = []

        for (index, step) in steps.enumerated() {
            switch step {
            case let .pair(r, p):
                let rc = refChords[r], pc = perfChords[p]
                lastRefBeats = rc.onsetBeats
                let pos = ScorePosition(quarters: rc.onsetBeats, timeSignature: ts)
                let common = rc.pitches.intersection(pc.pitches)
                let refRest = rc.pitches.subtracting(common).sorted()
                let perfRest = pc.pitches.subtracting(common).sorted()

                for pitch in common.sorted() {
                    results.append(NoteResult(kind: .correct, expectedPitch: pitch, playedPitch: pitch,
                                              position: pos, playedAt: pc.firstOnset(of: pitch)))
                }
                let wrong = min(refRest.count, perfRest.count)
                for k in 0..<wrong {
                    results.append(NoteResult(kind: .wrongPitch, expectedPitch: refRest[k], playedPitch: perfRest[k],
                                              position: pos, playedAt: pc.firstOnset(of: perfRest[k])))
                    flags.append(GradeFlag(kind: .wrongPitch, position: pos,
                                      message: "\(pos.label): played \(PitchName.of(perfRest[k])), expected \(PitchName.of(refRest[k]))"))
                }
                for pitch in refRest.dropFirst(wrong) {
                    results.append(NoteResult(kind: .missed, expectedPitch: pitch, playedPitch: nil, position: pos, playedAt: nil))
                    flags.append(GradeFlag(kind: .missed, position: pos, message: "\(pos.label): missed \(PitchName.of(pitch))"))
                }
                for pitch in perfRest.dropFirst(wrong) {
                    results.append(NoteResult(kind: .extra, expectedPitch: nil, playedPitch: pitch,
                                              position: pos, playedAt: pc.firstOnset(of: pitch)))
                    flags.append(GradeFlag(kind: .extra, position: pos, message: "\(pos.label): extra \(PitchName.of(pitch))"))
                }
                // Every paired event is a timing anchor, even a wrong note played on time.
                anchors.append(Anchor(beats: rc.onsetBeats, seconds: pc.onset, position: pos))

            case let .refOnly(r):
                let rc = refChords[r]
                lastRefBeats = rc.onsetBeats
                let pos = ScorePosition(quarters: rc.onsetBeats, timeSignature: ts)
                for pitch in rc.pitches.sorted() {
                    results.append(NoteResult(kind: .missed, expectedPitch: pitch, playedPitch: nil, position: pos, playedAt: nil))
                    flags.append(GradeFlag(kind: .missed, position: pos, message: "\(pos.label): missed \(PitchName.of(pitch))"))
                }

            case let .perfOnly(p):
                let pc = perfChords[p]
                if let f = firstMatch, index < f { ignoredLeading += pc.notes.count; continue }
                if let l = lastMatch, index > l { ignoredTrailing += pc.notes.count; continue }
                let pos = ScorePosition(quarters: lastRefBeats, timeSignature: ts)
                for pitch in pc.pitches.sorted() {
                    results.append(NoteResult(kind: .extra, expectedPitch: nil, playedPitch: pitch,
                                              position: pos, playedAt: pc.firstOnset(of: pitch)))
                    flags.append(GradeFlag(kind: .extra, position: pos, message: "\(pos.label): extra \(PitchName.of(pitch))"))
                }
            }
        }

        // Note counts.
        let correct = results.filter { $0.kind == .correct }.count
        let wrongPitch = results.filter { $0.kind == .wrongPitch }.count
        let missed = results.filter { $0.kind == .missed }.count
        let extra = results.filter { $0.kind == .extra }.count
        let expected = correct + wrongPitch + missed
        let accuracy = expected > 0 ? Double(correct) / Double(expected) : 0
        let score = expected > 0
            ? max(0, (Double(correct) - rubric.notes.extraNotePenalty * Double(extra)) / Double(expected))
            : 0
        let noteSummary = NoteSummary(expected: expected, correct: correct, wrongPitch: wrongPitch, missed: missed,
                                      extra: extra, ignoredLeading: ignoredLeading, ignoredTrailing: ignoredTrailing,
                                      accuracy: accuracy, score: score)

        // Timing.
        let targetBPM = rubric.targetBPM ?? reference.initialTempoBPM
        let timingResult = Self.timing(anchors: anchors, targetBPM: targetBPM, flagThreshold: rubric.rhythm.flagIOIError)
        if let t = timingResult { flags += t.flags }
        let timing = timingResult?.summary

        // Levels.
        var levels: [LevelResult] = []
        levels.append(LevelResult(
            check: .notes,
            passed: rubric.grades(.notes) ? score >= rubric.notes.minAccuracy : nil,
            value: score, threshold: rubric.notes.minAccuracy,
            detail: "\(Self.percent(score)) (\(correct)/\(expected) correct, \(wrongPitch) wrong, \(missed) missed, \(extra) extra)"
        ))

        let tooShort = refChords.count < 3
        if let t = timing {
            levels.append(LevelResult(
                check: .rhythm,
                passed: rubric.grades(.rhythm) ? t.meanIOIError <= rubric.rhythm.maxMeanIOIError : nil,
                value: t.meanIOIError, threshold: rubric.rhythm.maxMeanIOIError,
                detail: "mean interval error \(Self.percent(t.meanIOIError)), worst \(Self.percent(t.maxIOIError))"
            ))
            let tempoOK = abs(t.tempoDeviation) <= rubric.tempo.tolerance && t.steadinessCV <= rubric.tempo.maxSteadinessCV
            levels.append(LevelResult(
                check: .tempo,
                passed: rubric.grades(.tempo) ? tempoOK : nil,
                value: t.fittedBPM, threshold: targetBPM,
                detail: String(format: "%.0f bpm vs target %.0f (%+.0f%%), steadiness CV %.2f",
                               t.fittedBPM, t.targetBPM, t.tempoDeviation * 100, t.steadinessCV)
            ))
        } else {
            let why = tooShort ? "passage too short to judge timing" : "too few matched notes to judge timing"
            for check in [Rubric.Check.rhythm, .tempo] {
                let passed: Bool? = rubric.grades(check) ? tooShort : nil
                levels.append(LevelResult(check: check, passed: passed, value: nil, threshold: nil, detail: why))
            }
        }

        let passed = levels.allSatisfy { $0.passed ?? true }
        flags.sort { ($0.position.measure, $0.position.beat) < ($1.position.measure, $1.position.beat) }

        return GradeReport(passed: passed, rubricLevel: rubric.level, levels: levels, notes: noteSummary,
                           timing: timing, flags: flags, results: results)
    }

    // MARK: Timing

    struct Anchor {
        let beats: Double
        let seconds: Double
        let position: ScorePosition
    }

    struct TimingResult {
        let summary: TimingSummary
        let flags: [GradeFlag]
    }

    /// Fits seconds = a + b·beats over the anchors (least squares), then measures each
    /// inter-onset interval against b·(notated interval).
    static func timing(anchors: [Anchor], targetBPM: Double, flagThreshold: Double) -> TimingResult? {
        // Drop anchors that do not advance in the score (should not happen, but be safe).
        var pts: [Anchor] = []
        for a in anchors where pts.last.map({ a.beats > $0.beats + 1e-9 }) ?? true { pts.append(a) }
        guard pts.count >= 3 else { return nil }

        let n = Double(pts.count)
        let mx = pts.map(\.beats).reduce(0, +) / n
        let my = pts.map(\.seconds).reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for p in pts {
            sxy += (p.beats - mx) * (p.seconds - my)
            sxx += (p.beats - mx) * (p.beats - mx)
        }
        guard sxx > 0 else { return nil }
        let secondsPerQuarter = sxy / sxx
        guard secondsPerQuarter > 0 else { return nil }
        let fittedBPM = 60.0 / secondsPerQuarter

        var errors: [Double] = []
        var localTempos: [Double] = []
        var flags: [GradeFlag] = []
        var previousFlagSign = 0.0
        for k in 1..<pts.count {
            let dRef = pts[k].beats - pts[k - 1].beats
            let dPerf = pts[k].seconds - pts[k - 1].seconds
            let expected = secondsPerQuarter * dRef
            let signed = (dPerf - expected) / expected
            errors.append(abs(signed))
            localTempos.append(dPerf / dRef)

            if abs(signed) > flagThreshold {
                let sign: Double = signed > 0 ? 1 : -1
                // A single rushed note makes one short interval followed by one long one;
                // only flag the first of the pair.
                if previousFlagSign != 0 && sign == -previousFlagSign {
                    previousFlagSign = 0
                    continue
                }
                previousFlagSign = sign
                let pos = pts[k].position
                let kind: GradeFlag.Kind = signed > 0 ? .late : .early
                let word = signed > 0 ? "late" : "early"
                flags.append(GradeFlag(kind: kind, position: pos,
                                  message: "\(pos.label): came in \(percent(abs(signed))) \(word)"))
            } else {
                previousFlagSign = 0
            }
        }

        let mean = errors.reduce(0, +) / Double(errors.count)
        let tMean = localTempos.reduce(0, +) / Double(localTempos.count)
        let tVar = localTempos.map { ($0 - tMean) * ($0 - tMean) }.reduce(0, +) / Double(localTempos.count)
        let cv = tMean > 0 ? tVar.squareRoot() / tMean : 0

        let summary = TimingSummary(anchors: pts.count, fittedBPM: fittedBPM, targetBPM: targetBPM,
                                    tempoDeviation: (fittedBPM - targetBPM) / targetBPM,
                                    meanIOIError: mean, maxIOIError: errors.max() ?? 0, steadinessCV: cv)
        return TimingResult(summary: summary, flags: flags)
    }

    static func percent(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
}

extension ChordEvent {
    func firstOnset(of pitch: Int) -> Double? {
        notes.first(where: { $0.pitch == pitch })?.onset
    }
}
