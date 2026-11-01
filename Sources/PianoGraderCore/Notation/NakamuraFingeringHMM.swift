import Foundation

/// Which hand plays a note or exercise.
public enum Hand: String, Codable, Sendable {
    case right = "R", left = "L", both = "LR"
}

/// A note annotated with its assigned finger and hand.
public struct FingeredNote: Equatable, Sendable, Identifiable {
    public var id: String { "\(pitch)-\(quarter)-\(hand.rawValue)-\(finger)" }
    public var pitch: Int
    public var quarter: Double
    public var durationQuarters: Double
    public var hand: Hand
    /// Finger number 1–5 (1 = thumb, 2 = index, 3 = middle, 4 = ring, 5 = pinky).
    public var finger: Int
    public var measureNumber: Int?

    public init(pitch: Int, quarter: Double, durationQuarters: Double = 1.0, hand: Hand, finger: Int, measureNumber: Int? = nil) {
        self.pitch = pitch
        self.quarter = quarter
        self.durationQuarters = durationQuarters
        self.hand = hand
        self.finger = finger
        self.measureNumber = measureNumber
    }
}

/// Physical geometry of the piano keyboard used by Eita Nakamura's HMM.
public enum KeyboardGeometry {
    /// Horizontal offset within an octave in white-key width units (C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6).
    private static let octaveOffsets: [Double] = [
        0.0,   // C (white)
        0.55,  // C# (black)
        1.0,   // D (white)
        1.55,  // D# (black)
        2.0,   // E (white)
        3.0,   // F (white)
        3.55,  // F# (black)
        4.0,   // G (white)
        4.55,  // G# (black)
        5.0,   // A (white)
        5.55,  // A# (black)
        6.0    // B (white)
    ]

    private static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    public static func isBlackKey(_ pitch: Int) -> Bool {
        blackPitchClasses.contains(((pitch % 12) + 12) % 12)
    }

    /// Horizontal position along the keyboard in white-key width units.
    public static func x(_ pitch: Int) -> Double {
        let pc = ((pitch % 12) + 12) % 12
        let octave = (pitch / 12) - 1
        return Double(octave * 7) + octaveOffsets[pc]
    }

    /// Physical horizontal distance between two pitches in white-key width units.
    public static func distance(from p1: Int, to p2: Int) -> Double {
        x(p2) - x(p1)
    }
}

/// Automatic piano fingering generator using Eita Nakamura's Hidden Markov Model (HMM) formulation
/// with hand-position (frame) state representation.
/// Reference: Eita Nakamura et al., "Merged-Output Hidden Markov Model for Piano Fingering of Both Hands".
public struct NakamuraFingeringHMM: Sendable {

    /// Resting horizontal offset of a finger relative to the hand position (anchor).
    /// For Right Hand: anchor is finger 1 (thumb). Offsets are 0, 1, 2, 3, 4.
    /// For Left Hand: anchor is finger 5 (pinky). Offsets are 4, 3, 2, 1, 0.
    public static func relaxedOffset(finger: Int, hand: Hand) -> Double {
        if hand == .right {
            return Double(finger - 1)
        } else {
            return Double(5 - finger)
        }
    }

    /// Physical reach and key-topography cost for finger `f` when the hand is at anchor `xh`.
    public static func reachCost(pitch: Int, finger: Int, xh: Double, hand: Hand) -> Double {
        let xp = KeyboardGeometry.x(pitch)
        let neutral = xh + relaxedOffset(finger: finger, hand: hand)
        let reach = xp - neutral
        let absReach = abs(reach)

        var cost = absReach < 0.1 ? 0.0 : pow(absReach, 1.8) * 2.2
        let limit = (finger == 1 ? 1.5 : (finger == 5 ? 1.2 : 0.85))
        if absReach > limit {
            cost += (absReach - limit) * 16.0
        }

        // Nakamura black key penalty for thumb and pinky
        if KeyboardGeometry.isBlackKey(pitch) {
            if finger == 1 { cost += 2.5 }
            else if finger == 5 { cost += 1.5 }
        }

        // Finger naturalness / independence preference (Nakamura & Parncutt)
        // Fingers 1, 2, 3 are primary. Finger 4 is weakest and mechanically coupled; finger 5 is shorter.
        if finger == 4 {
            cost += 0.5
        } else if finger == 5 {
            cost += 0.2
        }

        return cost
    }

    /// Transition cost between consecutive notes with hand position awareness.
    public static func transitionCost(p1: Int, p2: Int, f1: Int, f2: Int, xh1: Double, xh2: Double, hand: Hand) -> Double {
        let dxh = xh2 - xh1
        let dp = KeyboardGeometry.x(p2) - KeyboardGeometry.x(p1)

        // 1. Repeated pitch
        if p1 == p2 {
            if f1 == f2 && abs(dxh) < 0.1 {
                return 0.0
            }
            if f1 != f2 {
                // Switching fingers on the same pitch is heavily penalized for basic passages
                return 22.0 + abs(dxh) * 5.0
            }
            return 10.0 + abs(dxh) * 4.0
        }

        // 2. Fixed hand position (in-hand fingering, no hand shift)
        if abs(dxh) < 0.1 {
            let fingerDist = abs(f1 - f2)
            let squeezePenalty = (abs(dp) <= 1.05 && fingerDist > 1) ? Double(fingerDist - 1) * 6.5 : 0.0

            if hand == .right {
                if dp > 0 {
                    // Ascending RH: fingers must ascend
                    if f2 > f1 {
                        let expectedDist = Double(f2 - f1)
                        let dev = abs(dp - expectedDist)
                        return dev * dev * 1.2 + squeezePenalty
                    } else {
                        // Anatomical inversion in-hand is impossible
                        return 50.0
                    }
                } else {
                    // Descending RH: fingers must descend
                    if f2 < f1 {
                        let expectedDist = Double(f1 - f2)
                        let dev = abs(abs(dp) - expectedDist)
                        return dev * dev * 1.2 + squeezePenalty
                    } else {
                        return 50.0
                    }
                }
            } else {
                // Left hand: fingers are inverted (5 = leftmost/lowest, 1 = rightmost/highest)
                if dp > 0 {
                    // Ascending LH: finger numbers must decrease (5 -> 4 -> 3 -> 2 -> 1)
                    if f2 < f1 {
                        let expectedDist = Double(f1 - f2)
                        let dev = abs(dp - expectedDist)
                        return dev * dev * 1.2 + squeezePenalty
                    } else {
                        return 50.0
                    }
                } else {
                    // Descending LH: finger numbers must increase (1 -> 2 -> 3 -> 4 -> 5)
                    if f2 > f1 {
                        let expectedDist = Double(f2 - f1)
                        let dev = abs(abs(dp) - expectedDist)
                        return dev * dev * 1.2 + squeezePenalty
                    } else {
                        return 50.0
                    }
                }
            }
        } else {
            // 3. Hand shift
            if hand == .right {
                // Non-thumb crossovers are anatomically impossible
                if dp > 0 && f2 <= f1 && f2 != 1 { return 50.0 }
                if dp < 0 && f2 >= f1 && f1 != 1 { return 50.0 }
                // Crossovers over thumb only valid for stepwise motion (<= 1.5 keys)
                if dp < -1.5 && f2 > 1 { return 40.0 }
                if dp > 1.5 && f2 == 1 { return 30.0 }

                // Scale pivot: thumb passing under (ascending)
                if dp > 0 && f2 == 1 && (f1 == 3 || f1 == 4) && dxh > 0 && dp <= 1.5 {
                    return 2.0 + abs(dxh - Double(f1)) * 0.7
                }
                // Scale pivot: finger crossing over thumb (descending)
                if dp < 0 && f1 == 1 && (f2 == 3 || f2 == 4) && dxh < 0 && abs(dp) <= 1.5 {
                    let base = f2 == 3 ? 1.5 : 8.5 // 4-over-1 is significantly more awkward than 3-over-1
                    return base + abs(abs(dxh) - Double(f2)) * 0.7
                }
            } else {
                // Left Hand
                // Non-thumb crossovers are anatomically impossible
                if dp > 0 && f2 >= f1 && f1 != 1 { return 50.0 }
                if dp < 0 && f2 <= f1 && f2 != 1 { return 50.0 }
                // Crossovers over thumb only valid for stepwise motion (<= 1.5 keys)
                if dp > 1.5 && f2 > 1 { return 40.0 }
                if dp < -1.5 && f2 == 1 { return 30.0 }

                // Scale pivot: finger crossing over thumb (ascending)
                if dp > 0 && f1 == 1 && (f2 == 3 || f2 == 4) && dxh > 0 && dp <= 1.5 {
                    let base = f2 == 3 ? 1.5 : 8.5
                    return base + abs(dxh - Double(f2)) * 0.7
                }
                // Scale pivot: thumb passing under (descending)
                if dp < 0 && f2 == 1 && (f1 == 3 || f1 == 4) && dxh < 0 && abs(dp) <= 1.5 {
                    return 2.0 + abs(abs(dxh) - Double(f1)) * 0.7
                }
            }

            // General hand repositioning penalty
            var cost = 5.5 + abs(dxh) * 1.2
            if hand == .right {
                if dp > 0 && f2 == 5 { cost += 12.0 } // Avoid landing on pinky when leaping up
                if dp < 0 && f2 == 1 && abs(dp) < 3.0 { cost += 8.0 }
            } else {
                if dp < 0 && f2 == 5 { cost += 12.0 } // Avoid landing on pinky when leaping down
                if dp > 0 && f2 == 1 && abs(dp) < 3.0 { cost += 8.0 }
            }
            return cost
        }
    }

    /// Solves the optimal finger sequence for a monophonic note sequence played by a single hand.
    public static func solveMonophonic(pitches: [Int], hand: Hand, anchors: [Int: Int] = [:]) -> [Int] {
        guard !pitches.isEmpty else { return [] }
        if pitches.count == 1 {
            if let a = anchors[0], (1...5).contains(a) { return [a] }
            return [hand == .right ? 1 : 5]
        }

        let n = pitches.count

        // Generate candidate anchor positions from the piece's pitches
        var candidateAnchorsSet = Set<Double>()
        for p in pitches {
            let xp = KeyboardGeometry.x(p)
            for f in 1...5 {
                let off = relaxedOffset(finger: f, hand: hand)
                candidateAnchorsSet.insert(xp - off)
            }
        }
        let candidateAnchors = Array(candidateAnchorsSet).sorted()

        struct State {
            let finger: Int
            let anchorIndex: Int
        }

        let states: [State] = (0..<candidateAnchors.count).flatMap { ai in
            (1...5).map { f in State(finger: f, anchorIndex: ai) }
        }
        let numStates = states.count

        var dp = [[Double]](repeating: [Double](repeating: Double.infinity, count: numStates), count: n)
        var backpointer = [[Int]](repeating: [Int](repeating: -1, count: numStates), count: n)

        // Initial step t = 0
        let p0 = pitches[0]
        let phrase = Array(pitches.prefix(min(pitches.count, 16)))
        let phraseXs = phrase.map { KeyboardGeometry.x($0) }
        let minX = phraseXs.min() ?? KeyboardGeometry.x(p0)
        let maxX = phraseXs.max() ?? KeyboardGeometry.x(p0)
        let phraseSpan = maxX - minX

        let targetAnchor: Double
        if hand == .right {
            if phraseSpan <= 4.0 {
                // In standard 5-finger position, thumb (finger 1) rests on the lowest note
                targetAnchor = minX
            } else {
                let x0 = KeyboardGeometry.x(p0)
                if abs(x0 - minX) <= 1.0 {
                    targetAnchor = x0
                } else if abs(x0 - maxX) <= 1.0 {
                    targetAnchor = x0 - 4.0
                } else {
                    targetAnchor = ((minX + maxX) / 2.0) - 2.0
                }
            }
        } else {
            if phraseSpan <= 4.0 {
                // In standard 5-finger position for left hand, pinky (finger 5) rests on lowest note
                targetAnchor = minX
            } else {
                let x0 = KeyboardGeometry.x(p0)
                if abs(x0 - minX) <= 1.0 {
                    targetAnchor = x0
                } else if abs(x0 - maxX) <= 1.0 {
                    targetAnchor = x0 - 4.0
                } else {
                    targetAnchor = ((minX + maxX) / 2.0) - 2.0
                }
            }
        }

        for (si, s) in states.enumerated() {
            if let explicitAnchor = anchors[0], explicitAnchor != s.finger { continue }
            let xh = candidateAnchors[s.anchorIndex]
            let rCost = reachCost(pitch: p0, finger: s.finger, xh: xh, hand: hand)
            if rCost < 25.0 {
                // Hand placement prior: prefer anchor matching target position
                let prior = abs(xh - targetAnchor) * 0.5
                dp[0][si] = rCost + prior
            }
        }

        // Trellis forward pass
        for t in 1..<n {
            let pPrev = pitches[t - 1]
            let pCurr = pitches[t]

            // Filter valid states for current note
            var activeCurrent: [(Int, State, Double)] = []
            for (si, s) in states.enumerated() {
                if let explicitAnchor = anchors[t], explicitAnchor != s.finger { continue }
                let xh = candidateAnchors[s.anchorIndex]
                let rCost = reachCost(pitch: pCurr, finger: s.finger, xh: xh, hand: hand)
                if rCost < 25.0 {
                    activeCurrent.append((si, s, rCost))
                }
            }

            for (currIdx, sCurr, rCost) in activeCurrent {
                let xhCurr = candidateAnchors[sCurr.anchorIndex]
                var bestCost = Double.infinity
                var bestPrev = -1

                for prevIdx in 0..<numStates {
                    let prevTotal = dp[t - 1][prevIdx]
                    guard prevTotal < Double.infinity else { continue }
                    let sPrev = states[prevIdx]
                    let xhPrev = candidateAnchors[sPrev.anchorIndex]

                    let tCost = transitionCost(p1: pPrev, p2: pCurr,
                                               f1: sPrev.finger, f2: sCurr.finger,
                                               xh1: xhPrev, xh2: xhCurr,
                                               hand: hand)
                    let total = prevTotal + tCost + rCost
                    if total < bestCost {
                        bestCost = total
                        bestPrev = prevIdx
                    }
                }

                dp[t][currIdx] = bestCost
                backpointer[t][currIdx] = bestPrev
            }
        }

        // Backtrack
        var bestEnd = 0
        var bestEndCost = Double.infinity
        for si in 0..<numStates {
            if dp[n - 1][si] < bestEndCost {
                bestEndCost = dp[n - 1][si]
                bestEnd = si
            }
        }

        var result = [Int](repeating: 1, count: n)
        var curr = bestEnd
        for t in (0..<n).reversed() {
            result[t] = states[curr].finger
            curr = backpointer[t][curr]
        }
        return result
    }

    /// Assigns fingers to a chord (notes occurring at the same onset) for a single hand.
    public static func solveChord(pitches: [Int], hand: Hand) -> [Int] {
        guard !pitches.isEmpty else { return [] }
        let sorted = pitches.sorted()
        let count = sorted.count

        if count == 1 {
            return [hand == .right ? 1 : 5]
        } else if count == 2 {
            let span = KeyboardGeometry.distance(from: sorted[0], to: sorted[1])
            if hand == .right {
                if span <= 2.2 { return [1, 2] }
                if span <= 3.2 { return [1, 3] }
                if span <= 4.2 { return [1, 4] }
                return [1, 5]
            } else {
                if span <= 2.2 { return [2, 1] }
                if span <= 3.2 { return [3, 1] }
                if span <= 4.2 { return [4, 1] }
                return [5, 1]
            }
        } else if count == 3 {
            return hand == .right ? [1, 3, 5] : [5, 3, 1]
        } else if count == 4 {
            return hand == .right ? [1, 2, 4, 5] : [5, 4, 2, 1]
        } else {
            return hand == .right ? [1, 2, 3, 4, 5] : [5, 4, 3, 2, 1]
        }
    }
}

/// High-level model for analyzing transcribed music and computing piano fingering.
public enum PianoFingeringModel {

    /// Analyzes a MIDI sequence and assigns piano fingerings.
    public static func analyze(sequence: MIDISequence, clef: Clef? = nil) -> [FingeredNote] {
        let validNotes = sequence.notes.filter { $0.channel != 9 }
        guard !validNotes.isEmpty else { return [] }

        // Split notes by hand (track 0 / channel 0 / pitch >= 60 to RH, else LH)
        var rightNotes: [NoteEvent] = []
        var leftNotes: [NoteEvent] = []

        let hasMultiTrack = Set(validNotes.map(\.track)).count > 1
        let hasMultiChannel = Set(validNotes.map(\.channel)).count > 1

        for n in validNotes {
            if let clef {
                if clef == .treble { rightNotes.append(n) } else { leftNotes.append(n) }
            } else if hasMultiTrack {
                if n.track == 0 { rightNotes.append(n) } else { leftNotes.append(n) }
            } else if hasMultiChannel {
                if n.channel == 0 { rightNotes.append(n) } else { leftNotes.append(n) }
            } else {
                if n.pitch >= 60 { rightNotes.append(n) } else { leftNotes.append(n) }
            }
        }

        var results: [FingeredNote] = []
        results += processHand(notes: rightNotes, hand: .right)
        results += processHand(notes: leftNotes, hand: .left)
        return results.sorted { ($0.quarter, $0.pitch) < ($1.quarter, $1.pitch) }
    }

    /// Analyzes a `PassageAnnotation` with its reference MIDI sequence.
    public static func analyze(passage: PassageAnnotation, sequence: MIDISequence) -> [FingeredNote] {
        let notes = analyze(sequence: sequence, clef: passage.clef)
        var out: [FingeredNote] = []
        for mutNote in notes {
            if let loc = passage.location(atQuarter: mutNote.quarter) {
                var copy = mutNote
                copy.measureNumber = loc.measure.number
                out.append(copy)
            } else {
                out.append(mutNote)
            }
        }
        return out
    }

    /// Analyzes a `Score` and produces fingered notes.
    public static func analyze(score: Score) -> [FingeredNote] {
        var results: [FingeredNote] = []
        let sixteenthsPerQuarter = Double(Score.sixteenthsPerQuarter)

        for staffIndex in score.staves.indices {
            let hand: Hand = staffIndex == 0 ? .right : .left
            var staffNotes: [(pitch: Int, quarter: Double, durationQuarters: Double, measure: Int)] = []

            for m in score.measures {
                for event in m.events(onStaff: staffIndex) where !event.isRest && !event.notes.allSatisfy(\.tieStop) {
                    let quarter = Double(m.startSixteenth + event.start) / sixteenthsPerQuarter
                    let dur = Double(event.duration) / sixteenthsPerQuarter
                    for note in event.notes where !note.tieStop {
                        staffNotes.append((note.midi, quarter, dur, m.number))
                    }
                }
            }

            guard !staffNotes.isEmpty else { continue }
            // Group by onset for monophonic vs chord
            var chordGroups: [[(pitch: Int, quarter: Double, durationQuarters: Double, measure: Int)]] = []
            var currentGroup: [(pitch: Int, quarter: Double, durationQuarters: Double, measure: Int)] = []

            for note in staffNotes {
                if let last = currentGroup.last, abs(last.quarter - note.quarter) > 0.05 {
                    chordGroups.append(currentGroup)
                    currentGroup = [note]
                } else {
                    currentGroup.append(note)
                }
            }
            if !currentGroup.isEmpty { chordGroups.append(currentGroup) }

            // If monophonic: solve with HMM
            if chordGroups.allSatisfy({ $0.count == 1 }) {
                let pitches = chordGroups.map { $0[0].pitch }
                let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: hand)
                for (i, group) in chordGroups.enumerated() {
                    let n = group[0]
                    results.append(FingeredNote(pitch: n.pitch, quarter: n.quarter, durationQuarters: n.durationQuarters,
                                                hand: hand, finger: fingers[i], measureNumber: n.measure))
                }
            } else {
                for group in chordGroups {
                    let pitches = group.map(\.pitch)
                    let fingers = NakamuraFingeringHMM.solveChord(pitches: pitches, hand: hand)
                    for (i, n) in group.enumerated() {
                        results.append(FingeredNote(pitch: n.pitch, quarter: n.quarter, durationQuarters: n.durationQuarters,
                                                    hand: hand, finger: fingers[min(i, fingers.count - 1)], measureNumber: n.measure))
                    }
                }
            }
        }

        return results.sorted { ($0.quarter, $0.pitch) < ($1.quarter, $1.pitch) }
    }

    private static func processHand(notes: [NoteEvent], hand: Hand) -> [FingeredNote] {
        guard !notes.isEmpty else { return [] }
        let sorted = notes.sorted { ($0.onsetBeats, $0.pitch) < ($1.onsetBeats, $1.pitch) }

        // Group by onset beat
        var groups: [[NoteEvent]] = []
        var current: [NoteEvent] = []

        for n in sorted {
            if let last = current.last, abs(last.onsetBeats - n.onsetBeats) > 0.05 {
                groups.append(current)
                current = [n]
            } else {
                current.append(n)
            }
        }
        if !current.isEmpty { groups.append(current) }

        var results: [FingeredNote] = []

        // If mostly monophonic
        if groups.allSatisfy({ $0.count == 1 }) {
            let pitches = groups.map { $0[0].pitch }
            let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: hand)
            for (i, g) in groups.enumerated() {
                let n = g[0]
                let dur = n.offsetBeats.map { $0 - n.onsetBeats } ?? (n.offset - n.onset)
                results.append(FingeredNote(pitch: n.pitch, quarter: n.onsetBeats, durationQuarters: max(0.25, dur),
                                            hand: hand, finger: fingers[i]))
            }
        } else {
            // Mixed or polyphonic
            for g in groups {
                let pitches = g.map(\.pitch)
                let fingers = NakamuraFingeringHMM.solveChord(pitches: pitches, hand: hand)
                for (i, n) in g.enumerated() {
                    let dur = n.offsetBeats.map { $0 - n.onsetBeats } ?? (n.offset - n.onset)
                    results.append(FingeredNote(pitch: n.pitch, quarter: n.onsetBeats, durationQuarters: max(0.25, dur),
                                                hand: hand, finger: fingers[min(i, fingers.count - 1)]))
                }
            }
        }

        return results
    }
}
