import Foundation

/// Positions for drawing a `Score`: systems (lines of music) stacked down the page,
/// measures across each system, and an x for every onset. Units are points; y grows downwards.
/// Pure geometry, so the drawing code only has to place glyphs.
public struct ScoreLayout: Sendable {
    public struct Metrics: Sendable {
        /// Distance between staff lines.
        public var spacing: Double = 9
        /// Space between the bottom line of one staff and the top line of the next in a system.
        public var staffGap: Double = 7      // in spacings
        /// Room above the top staff and below the bottom staff for ledger lines and stems.
        public var systemMargin: Double = 4.5 // in spacings
        /// Extra space between systems.
        public var systemGap: Double = 1.5    // in spacings
        /// Print the time signature on the first system (off for single-symbol pictures).
        public var timeSignature = true

        public init(spacing: Double = 9) { self.spacing = spacing }
    }

    public struct MeasureLayout: Sendable {
        public var index: Int
        public var x: Double
        public var width: Double
        /// x of each onset in the measure, keyed by its start in sixteenths.
        public var columns: [Int: Double]

        public var maxX: Double { x + width }
    }

    public struct System: Sendable {
        public var index: Int
        /// Top of the system's band (above the ledger-line margin).
        public var top: Double
        public var height: Double
        /// y of each staff's top line.
        public var staffTops: [Double]
        public var x: Double
        public var width: Double
        /// Width of the clef, key signature and (first system only) time signature.
        public var headerWidth: Double
        public var showsTimeSignature: Bool
        public var measures: [MeasureLayout]
    }

    public let score: Score
    public let metrics: Metrics
    public let width: Double
    public private(set) var systems: [System] = []

    public var height: Double {
        (systems.last.map { $0.top + $0.height } ?? 0) + metrics.spacing
    }

    public init(score: Score, width: Double, metrics: Metrics = Metrics()) {
        self.score = score
        self.metrics = metrics
        self.width = max(200, width)
        self.systems = layOut()
    }

    // MARK: Queries

    /// y of a line or space on a staff: step 0 is the bottom line, 8 the top line.
    public func y(ofStep step: Int, staff: Int, system: Int) -> Double {
        let top = systems[system].staffTops[staff]
        return top + 4 * metrics.spacing - Double(step) * metrics.spacing / 2
    }

    /// Where a point in the music falls: the system and the x of the onset at or before it.
    /// `quarter` counts quarter notes from the start of the score.
    public func position(atQuarter quarter: Double) -> (system: Int, x: Double, measure: Int)? {
        guard let m = score.measureIndex(atQuarter: quarter) else { return nil }
        let measure = score.measures[m]
        let local = Int((quarter * Double(Score.sixteenthsPerQuarter)).rounded()) - measure.startSixteenth
        for system in systems {
            guard let ml = system.measures.first(where: { $0.index == m }) else { continue }
            let starts = ml.columns.keys.sorted()
            let at = starts.last(where: { $0 <= local }) ?? starts.first ?? 0
            return (system.index, ml.columns[at] ?? ml.x, m)
        }
        return nil
    }

    /// The measure (index into `score.measures`) at a point of the drawing, if any.
    public func measureIndex(atX x: Double, y: Double) -> Int? {
        guard let system = systems.first(where: { y >= $0.top && y < $0.top + $0.height }) else { return nil }
        return system.measures.first(where: { x >= $0.x && x < $0.maxX })?.index
    }

    /// A note found under a point: its pitch and written length.
    public struct NoteHit: Equatable, Sendable {
        public var midi: Int
        /// Written length in quarter notes (dots included).
        public var quarters: Double
    }

    /// The note whose head is at (or very near) a point of the drawing, or nil over rests,
    /// staff lines and empty space. The closest head wins in a chord.
    public func note(atX x: Double, y: Double) -> NoteHit? {
        guard let system = systems.first(where: { y >= $0.top && y < $0.top + $0.height }),
              let ml = system.measures.first(where: { x >= $0.x && x < $0.maxX }) else { return nil }
        let s = metrics.spacing
        var best: (hit: NoteHit, distance: Double)?
        for event in score.measures[ml.index].events where !event.isRest {
            guard let cx = ml.columns[event.start], abs(x - cx) <= 1.6 * s,
                  event.staff < score.staves.count else { continue }
            let clef = score.staves[event.staff]
            for note in event.notes {
                let dy = abs(y - self.y(ofStep: clef.staffStep(of: note.spelled), staff: event.staff, system: system.index))
                guard dy <= 0.75 * s else { continue }
                let distance = dy + abs(x - cx) / 4
                let hit = NoteHit(midi: note.midi, quarters: Double(event.duration) / Double(Score.sixteenthsPerQuarter))
                if best.map({ distance < $0.distance }) ?? true { best = (hit, distance) }
            }
        }
        return best?.hit
    }

    // MARK: Layout

    /// Width of the column for an onset, by the shortest note starting there.
    private func columnWidth(duration: Int, hasAccidental: Bool) -> Double {
        let s = metrics.spacing
        let base: Double
        switch duration {
        case ..<2: base = 2.4
        case 2: base = 2.9
        case 3: base = 3.3
        case 4..<6: base = 3.8
        case 6..<8: base = 4.4
        case 8..<12: base = 5.2
        default: base = 6.2
        }
        return (base + (hasAccidental ? 1.3 : 0)) * s
    }

    private func naturalColumns(_ measure: ScoreMeasure) -> [(start: Int, width: Double)] {
        var shortest: [Int: Int] = [:]
        var accidental: Set<Int> = []
        for e in measure.events {
            shortest[e.start] = min(shortest[e.start] ?? Int.max, e.duration)
            if e.notes.contains(where: { $0.accidental != nil }) { accidental.insert(e.start) }
        }
        return shortest.keys.sorted().map { start in
            (start, columnWidth(duration: shortest[start]!, hasAccidental: accidental.contains(start)))
        }
    }

    private func headerWidth(timeSignature: Bool) -> Double {
        let s = metrics.spacing
        return 4.2 * s + Double(abs(score.key.fifths)) * 1.1 * s + (timeSignature ? 3.0 * s : 0) + 1.0 * s
    }

    private func layOut() -> [System] {
        let s = metrics.spacing
        let padding = (left: 1.4 * s, right: 1.0 * s)
        let natural = score.measures.map { m -> (columns: [(start: Int, width: Double)], width: Double) in
            let cols = naturalColumns(m)
            return (cols, padding.left + cols.reduce(0) { $0 + $1.width } + padding.right)
        }

        // Greedy line breaking.
        var lines: [[Int]] = []
        var current: [Int] = []
        var used = 0.0
        for (i, n) in natural.enumerated() {
            let available = width - headerWidth(timeSignature: lines.isEmpty && metrics.timeSignature)
            if !current.isEmpty && used + n.width > available {
                lines.append(current)
                current = []
                used = 0
            }
            current.append(i)
            used += n.width
        }
        if !current.isEmpty { lines.append(current) }

        let staffCount = score.staves.count
        let staffBlock = Double(staffCount) * 4 * s + Double(max(0, staffCount - 1)) * metrics.staffGap * s
        let systemHeight = staffBlock + 2 * metrics.systemMargin * s

        var systems: [System] = []
        var top = 0.0
        for (index, line) in lines.enumerated() {
            let showTime = index == 0 && metrics.timeSignature
            let header = headerWidth(timeSignature: showTime)
            let available = width - header
            let used = line.reduce(0) { $0 + natural[$1].width }
            // Justify every system except a short last one.
            let isLast = index == lines.count - 1
            let stretch = (isLast && used < 0.75 * available) ? 1.0 : max(1.0, available / max(1, used))

            var x = header
            var measures: [MeasureLayout] = []
            for m in line {
                let n = natural[m]
                let w = n.width * stretch
                let columnScale = (w - padding.left - padding.right) / max(1, n.width - padding.left - padding.right)
                var columns: [Int: Double] = [:]
                var cx = x + padding.left
                for col in n.columns {
                    columns[col.start] = cx + 0.6 * s // notehead centre sits a little into its column
                    cx += col.width * columnScale
                }
                measures.append(MeasureLayout(index: m, x: x, width: w, columns: columns))
                x += w
            }

            let firstStaffTop = top + metrics.systemMargin * s
            let staffTops = (0..<staffCount).map { firstStaffTop + Double($0) * (4 + metrics.staffGap) * s }
            systems.append(System(index: index, top: top, height: systemHeight, staffTops: staffTops,
                                  x: 0, width: x, headerWidth: header, showsTimeSignature: showTime, measures: measures))
            top += systemHeight + metrics.systemGap * s
        }
        return systems
    }
}

extension ScoreEvent {
    /// Stem direction by the usual rule: notes mostly above the middle line take a down stem.
    public func stemUp(clef: Clef) -> Bool {
        guard !notes.isEmpty else { return true }
        let steps = notes.map { clef.staffStep(of: $0.spelled) }
        let farthestAbove = (steps.max() ?? 4) - 4
        let farthestBelow = 4 - (steps.min() ?? 4)
        return farthestBelow > farthestAbove // a note on the middle line takes a down stem
    }
}
