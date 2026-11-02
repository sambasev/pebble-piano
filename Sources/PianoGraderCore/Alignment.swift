import Foundation

/// Notes that start together (within the chord window) treated as one event.
public struct ChordEvent: Sendable {
    public var notes: [NoteEvent]

    public init(notes: [NoteEvent]) { self.notes = notes }

    public var onset: Double { notes.map(\.onset).min() ?? 0 }
    public var onsetBeats: Double { notes.map(\.onsetBeats).min() ?? 0 }
    public var pitches: Set<Int> { Set(notes.map(\.pitch)) }
}

public enum ChordGrouping {
    /// Groups notes whose onsets fall within `window` seconds of the first note of the group.
    public static func group(_ notes: [NoteEvent], window: Double) -> [ChordEvent] {
        let sorted = notes.sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
        var chords: [ChordEvent] = []
        var current: [NoteEvent] = []
        for n in sorted {
            if let first = current.first, n.onset - first.onset > window {
                chords.append(ChordEvent(notes: current))
                current = []
            }
            current.append(n)
        }
        if !current.isEmpty { chords.append(ChordEvent(notes: current)) }
        return chords
    }
}

public enum AlignmentStep: Equatable, Sendable {
    /// A reference event paired with a performed event (they may differ in pitch).
    case pair(ref: Int, perf: Int)
    /// A reference event with nothing played for it.
    case refOnly(Int)
    /// A performed event with no reference counterpart.
    case perfOnly(Int)
}

public enum Aligner {
    /// Cost of skipping one event on either side.
    static let gapCost = 1.0

    /// Cost of pairing two events: 0 for identical pitch sets, 1 for disjoint ones.
    /// Because a full mismatch (1) is cheaper than two gaps (2), a wrong note is
    /// reported as a wrong pitch rather than as a miss plus an extra.
    static func substitutionCost(_ a: Set<Int>, _ b: Set<Int>) -> Double {
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return 1.0 - Double(a.intersection(b).count) / Double(union)
    }

    /// Where each event falls in its passage, 0 at the first onset to 1 at the last.
    static func relativePositions(_ events: [ChordEvent]) -> [Double] {
        guard let first = events.first?.onset, let last = events.last?.onset, last > first else {
            return events.map { _ in 0 }
        }
        return events.map { ($0.onset - first) / (last - first) }
    }

    /// Global alignment (Needleman–Wunsch) of reference and performance chord events.
    ///
    /// When pitches alone allow several equally good alignments (a skipped bar whose notes
    /// also occur in the bar before), pairs are preferred whose events fall at the same point
    /// of their passages. That tie-break adds at most 0.01 in all, less than any real
    /// difference in pitch cost, so it never changes how many notes match.
    public static func align(reference: [ChordEvent], performance: [ChordEvent]) -> [AlignmentStep] {
        let n = reference.count, m = performance.count
        let refPositions = relativePositions(reference)
        let perfPositions = relativePositions(performance)
        let tieWeight = 0.01 / Double(max(1, n, m))
        let refSets = reference.map(\.pitches)
        let perfSets = performance.map(\.pitches)
        func pairCost(_ i: Int, _ j: Int) -> Double {
            substitutionCost(refSets[i], perfSets[j]) + tieWeight * abs(refPositions[i] - perfPositions[j])
        }

        // cost[i][j] = best cost aligning ref[0..<i] with perf[0..<j]
        var cost = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = Double(i) * gapCost }
        for j in 0...m { cost[0][j] = Double(j) * gapCost }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let diag = cost[i - 1][j - 1] + pairCost(i - 1, j - 1)
                    let up = cost[i - 1][j] + gapCost
                    let left = cost[i][j - 1] + gapCost
                    cost[i][j] = min(diag, up, left)
                }
            }
        }

        // Trace back, preferring pairs on ties.
        var steps: [AlignmentStep] = []
        var i = n, j = m
        let eps = 1e-9
        while i > 0 || j > 0 {
            if i > 0, j > 0,
               abs(cost[i][j] - (cost[i - 1][j - 1] + pairCost(i - 1, j - 1))) < eps {
                steps.append(.pair(ref: i - 1, perf: j - 1))
                i -= 1; j -= 1
            } else if i > 0, abs(cost[i][j] - (cost[i - 1][j] + gapCost)) < eps {
                steps.append(.refOnly(i - 1))
                i -= 1
            } else {
                steps.append(.perfOnly(j - 1))
                j -= 1
            }
        }
        return steps.reversed()
    }
}
