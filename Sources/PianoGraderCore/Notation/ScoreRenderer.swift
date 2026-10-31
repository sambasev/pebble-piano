import Foundation

/// A note of the reference the player has played correctly: its start (quarter notes from
/// the beginning, as in the MIDI file) and pitch.
public struct PlayedNote: Hashable, Sendable {
    public var quarter: Double
    public var pitch: Int

    public init(quarter: Double, pitch: Int) {
        self.quarter = quarter
        self.pitch = pitch
    }
}

/// Live state drawn over a score.
public struct ScoreOverlay: Sendable {
    /// Playhead position in quarter notes from the start; nil hides it.
    public var cursorQuarter: Double?
    /// The playhead follows the reference audio rather than waiting for the player.
    public var auditioning: Bool
    /// Pitches the guide is waiting for: drawn blue at the playhead.
    public var expected: Set<Int>
    /// Notes played correctly so far: drawn green.
    public var played: [PlayedNote]
    /// Pitches played that the guide did not expect: drawn red beside the playhead.
    public var wrong: Set<Int>
    /// After grading: measure numbers with mistakes. nil before grading.
    public var mistakeMeasures: Set<Int>?
    /// Finger numbers (1–5) over the top staff's notes in score order (see `renderFingering`).
    public var fingering: [Int]

    public init(cursorQuarter: Double? = nil, auditioning: Bool = false, expected: Set<Int> = [],
                played: [PlayedNote] = [], wrong: Set<Int> = [], mistakeMeasures: Set<Int>? = nil,
                fingering: [Int] = []) {
        self.cursorQuarter = cursorQuarter
        self.auditioning = auditioning
        self.expected = expected
        self.played = played
        self.wrong = wrong
        self.mistakeMeasures = mistakeMeasures
        self.fingering = fingering
    }
}

/// Engraves a laid-out score into drawing items. Proportions follow Bravura's engraving
/// defaults (staff line 0.13 spaces, stem 0.12, beam 0.5, stems about 3.5 spaces).
public struct ScoreRenderer {
    public let layout: ScoreLayout
    private var s: Double { layout.metrics.spacing }
    private var score: Score { layout.score }

    public init(layout: ScoreLayout) { self.layout = layout }

    /// Everything in one drawing (used for SVG): score, grading tints, playhead and marks.
    public func render(_ overlay: ScoreOverlay = ScoreOverlay()) -> Drawing {
        var drawing = renderScore(mistakeMeasures: overlay.mistakeMeasures, fingering: overlay.fingering)
        let live = renderLive(overlay)
        // The playhead band goes behind the music; the marks on top.
        let bandCount = live.prefix { if case .rect = $0 { return true } else { return false } }.count
        let tintCount = drawing.items.prefix { if case .rect = $0 { return true } else { return false } }.count
        drawing.items.insert(contentsOf: live.prefix(bandCount), at: tintCount)
        drawing.items += renderPlayed(overlay.played)
        drawing.items += live.dropFirst(bandCount)
        return drawing
    }

    /// The engraved score, with red and green measure tints after grading, and finger numbers
    /// when given. Changes rarely, so the app draws it once and keeps it.
    public func renderScore(mistakeMeasures: Set<Int>? = nil, fingering: [Int] = []) -> Drawing {
        var items: [DrawItem] = []
        if let mistakes = mistakeMeasures {
            for system in layout.systems {
                for m in system.measures {
                    let number = score.measures[m.index].number
                    let (top, bottom) = staffSpan(system)
                    items.append(.rect(x: m.x, y: top - 1.5 * s, width: m.width, height: bottom - top + 3 * s, cornerRadius: 0,
                                       color: mistakes.contains(number) ? .mistakeTint : .cleanTint))
                }
            }
        }
        for system in layout.systems {
            items += staffLines(system)
            items += header(system)
            items += barlines(system)
            for ml in system.measures {
                for staff in score.staves.indices {
                    items += events(measure: score.measures[ml.index], layout: ml, staff: staff, system: system, colorFor: nil)
                }
            }
        }
        items += ties()
        items += renderFingering(fingering)
        if let mistakes = mistakeMeasures {
            for system in layout.systems {
                for m in system.measures where mistakes.contains(score.measures[m.index].number) {
                    let number = score.measures[m.index].number
                    items.append(.text("check m\(number)", at: DrawPoint(m.x + 0.4 * s, staffSpan(system).top - 1.9 * s), size: 1.25 * s,
                                       color: .wrong, anchor: .leading, bold: true))
                }
            }
        }
        return Drawing(width: layout.width, height: layout.height, items: items)
    }

    /// What moves while playing, apart from the playhead itself (`renderPlayhead`): a halo
    /// behind each note still wanted, those notes in blue over the score's own noteheads, and
    /// wrong notes in red.
    public func renderLive(_ overlay: ScoreOverlay) -> [DrawItem] {
        guard let quarter = overlay.cursorQuarter, let cursor = layout.position(atQuarter: quarter) else { return [] }
        let system = layout.systems[cursor.system]
        var items: [DrawItem] = []

        // The chord under the playhead: redraw the notes still wanted in blue.
        let measure = score.measures[cursor.measure]
        if !overlay.expected.isEmpty, let ml = system.measures.first(where: { $0.index == cursor.measure }) {
            let local = Int((quarter * Double(Score.sixteenthsPerQuarter)).rounded()) - measure.startSixteenth
            for staff in score.staves.indices {
                guard let start = measure.events(onStaff: staff).last(where: { $0.start <= local })?.start else { continue }
                let marked = events(measure: measure, layout: ml, staff: staff, system: system,
                                    colorFor: { event, pitch in event.start == start && overlay.expected.contains(pitch) ? .expected : .ink })
                let wanted = marked.filter { item in
                    if case .glyph(_, _, _, .expected) = item { return true }
                    return false
                }
                // A halo behind each wanted notehead (glyph origins sit at the notehead's left, on its centre line).
                for case .glyph(let glyph, let at, _, _) in wanted where glyph.isNotehead {
                    items.append(.rect(x: at.x - 0.55 * s, y: at.y - 0.95 * s, width: 2.3 * s, height: 1.9 * s,
                                       cornerRadius: 0.95 * s, color: .expectedHalo))
                }
                items += wanted
            }
        }

        // Keys held that the guide didn't expect, in the playhead's column on their staff.
        if !overlay.wrong.isEmpty {
            for (staff, pitches) in Dictionary(grouping: overlay.wrong, by: { score.staff(forPitch: $0) }).sorted(by: { $0.key < $1.key }) {
                items += PlayedNoteMarks.items(pitches: pitches.sorted(), key: score.key, clef: score.staves[staff],
                                               x: cursor.x, spacing: s,
                                               yOfStep: { layout.y(ofStep: $0, staff: staff, system: cursor.system) })
            }
        }
        return items
    }

    /// The playhead on its own (so the app can pulse it): a see-through band reaching well
    /// above and below the staves, in the audition colour while the reference plays.
    public func renderPlayhead(_ overlay: ScoreOverlay) -> [DrawItem] {
        guard let quarter = overlay.cursorQuarter, let cursor = layout.position(atQuarter: quarter) else { return [] }
        let (top, bottom) = staffSpan(layout.systems[cursor.system])
        let bandTop = top - 4 * s, bandBottom = bottom + 4 * s
        let half = 1.1 * s
        return [.rect(x: cursor.x - half, y: bandTop, width: 2 * half, height: bandBottom - bandTop,
                      cornerRadius: half, color: overlay.auditioning ? .audition : .cursor)]
    }

    /// The notes played correctly, in green, to draw over the score: noteheads with their
    /// accidentals and dots, and the stem, flag and beam once the whole chord (or beamed group)
    /// is played. A tied note turns green along its whole length.
    public func renderPlayed(_ played: [PlayedNote]) -> [DrawItem] {
        guard !played.isEmpty else { return [] }
        struct Key: Hashable { var sixteenth: Int; var midi: Int }
        var keys = Set(played.map { Key(sixteenth: Int(($0.quarter * Double(Score.sixteenthsPerQuarter)).rounded()), midi: $0.pitch) })

        // Tied continuations belong to the note they continue.
        for staff in score.staves.indices {
            var origin: [Int: Key] = [:] // midi → the note a tie started from
            for m in score.measures {
                for e in m.events(onStaff: staff) where !e.isRest {
                    for n in e.notes {
                        let key = Key(sixteenth: m.startSixteenth + e.start, midi: n.midi)
                        let from = n.tieStop ? origin[n.midi] : nil
                        if let from, keys.contains(from) { keys.insert(key) }
                        origin[n.midi] = n.tieStart ? (from ?? key) : nil
                    }
                }
            }
        }

        let touched = Set(keys.compactMap { score.measureIndex(atQuarter: Double($0.sixteenth) / Double(Score.sixteenthsPerQuarter)) })
        var items: [DrawItem] = []
        for system in layout.systems {
            for ml in system.measures where touched.contains(ml.index) {
                let measure = score.measures[ml.index]
                for staff in score.staves.indices {
                    let marked = events(measure: measure, layout: ml, staff: staff, system: system, colorFor: { event, pitch in
                        keys.contains(Key(sixteenth: measure.startSixteenth + event.start, midi: pitch)) ? .played : .ink
                    })
                    items += marked.filter { item in
                        switch item {
                        case .glyph(_, _, _, .played), .line(_, _, _, .played), .shape(_, .played): return true
                        default: return false
                        }
                    }
                }
            }
        }
        return items
    }

    /// Finger numbers over the top staff: one per note or chord, in score order (rests and
    /// tied continuations get none). Extra numbers are ignored; with fewer, later notes go
    /// unmarked. Each sits above the staff, or above the note when it's higher than that.
    public func renderFingering(_ fingers: [Int]) -> [DrawItem] {
        guard !fingers.isEmpty, let clef = score.staves.first else { return [] }
        var items: [DrawItem] = []
        var next = 0
        for system in layout.systems {
            for ml in system.measures {
                for event in score.measures[ml.index].events(onStaff: 0).sorted(by: { $0.start < $1.start }) {
                    guard next < fingers.count else { return items }
                    guard !event.isRest, !event.notes.allSatisfy(\.tieStop), let x = ml.columns[event.start] else { continue }
                    // 0: no finger number printed for this note (books print them only now and then).
                    guard fingers[next] > 0 else { next += 1; continue }
                    let highest = event.notes.map { clef.staffStep(of: $0.spelled) }.max() ?? 0
                    let aboveStaff = layout.y(ofStep: 8, staff: 0, system: system.index) - 1.4 * s
                    let aboveNote = layout.y(ofStep: highest, staff: 0, system: system.index) - 4.6 * s
                    items.append(.text(String(fingers[next]), at: DrawPoint(x, min(aboveStaff, aboveNote)),
                                       size: 1.4 * s, color: .ink, anchor: .center, bold: true))
                    next += 1
                }
            }
        }
        return items
    }

    // MARK: Staff furniture

    private func staffSpan(_ system: ScoreLayout.System) -> (top: Double, bottom: Double) {
        (system.staffTops.first ?? system.top, (system.staffTops.last ?? system.top) + 4 * s)
    }

    private func staffLines(_ system: ScoreLayout.System) -> [DrawItem] {
        var items: [DrawItem] = []
        for top in system.staffTops {
            for line in 0..<5 {
                let y = top + Double(line) * s
                items.append(.line(from: DrawPoint(system.x, y), to: DrawPoint(system.x + system.width, y), width: 0.13 * s, color: .ink))
            }
        }
        // The system's left edge joins its staves.
        let (top, bottom) = staffSpan(system)
        items.append(.line(from: DrawPoint(system.x, top), to: DrawPoint(system.x, bottom), width: 0.16 * s, color: .ink))
        return items
    }

    private func header(_ system: ScoreLayout.System) -> [DrawItem] {
        var items: [DrawItem] = []
        for (staff, clef) in score.staves.enumerated() {
            let y = { (step: Int) in layout.y(ofStep: step, staff: staff, system: system.index) }
            var x = system.x + 0.8 * s
            switch clef {
            case .treble: items.append(.glyph(.gClef, at: DrawPoint(x, y(2)), size: s, color: .ink))
            case .bass: items.append(.glyph(.fClef, at: DrawPoint(x, y(6)), size: s, color: .ink))
            }
            x += 3.4 * s
            for step in Self.keySignatureSteps(score.key, clef: clef) {
                let glyph: Glyph = score.key.fifths > 0 ? .accidentalSharp : .accidentalFlat
                items.append(.glyph(glyph, at: DrawPoint(x, y(step)), size: s, color: .ink))
                x += 1.1 * s
            }
            if system.showsTimeSignature {
                x += 0.4 * s
                items += timeSignatureDigits(score.timeSignature.numerator, centreX: x + 0.9 * s, y: y(6))
                items += timeSignatureDigits(score.timeSignature.denominator, centreX: x + 0.9 * s, y: y(2))
            }
            // A measure number at the start of each later system.
            if staff == 0, system.index > 0, let first = system.measures.first {
                items.append(.text(String(score.measures[first.index].number), at: DrawPoint(system.x + 0.2 * s, system.staffTops[0] - 1.4 * s),
                                   size: 1.2 * s, color: .faint, anchor: .leading, bold: false))
            }
        }
        return items
    }

    /// Lines or spaces holding the key signature's sharps or flats, in the order they are written.
    static func keySignatureSteps(_ key: KeySignature, clef: Clef) -> [Int] {
        let sharps = [8, 5, 9, 6, 3, 7, 4]   // F C G D A E B on the treble staff
        let flats = [4, 7, 3, 6, 2, 5, 1]    // B E A D G C F
        let shift = clef == .treble ? 0 : -2
        if key.fifths > 0 { return sharps.prefix(key.fifths).map { $0 + shift } }
        if key.fifths < 0 { return flats.prefix(-key.fifths).map { $0 + shift } }
        return []
    }

    private func timeSignatureDigits(_ value: Int, centreX: Double, y: Double) -> [DrawItem] {
        let digits = String(value).compactMap { $0.wholeNumberValue }.compactMap { Glyph(rawValue: "timeSig\($0)") }
        let total = digits.reduce(0) { $0 + $1.width * s }
        var x = centreX - total / 2
        return digits.map { glyph in
            defer { x += glyph.width * s }
            return .glyph(glyph, at: DrawPoint(x, y), size: s, color: .ink)
        }
    }

    private func barlines(_ system: ScoreLayout.System) -> [DrawItem] {
        let (top, bottom) = staffSpan(system)
        var items: [DrawItem] = []
        for ml in system.measures {
            let x = ml.maxX
            if ml.index == score.measures.count - 1 {
                items.append(.line(from: DrawPoint(x - 0.9 * s, top), to: DrawPoint(x - 0.9 * s, bottom), width: 0.16 * s, color: .ink))
                items.append(.rect(x: x - 0.5 * s, y: top, width: 0.5 * s, height: bottom - top, cornerRadius: 0, color: .ink))
            } else {
                items.append(.line(from: DrawPoint(x, top), to: DrawPoint(x, bottom), width: 0.16 * s, color: .ink))
            }
        }
        return items
    }

    // MARK: Notes and rests

    private struct Placed {
        var stemX: Double
        var stemUp: Bool
        var noteEndY: Double   // the stem starts at the far note
        var nearY: Double      // the note nearest the stem tip
        var tipY: Double       // where the stem ends without a beam
    }

    private func events(measure: ScoreMeasure, layout ml: ScoreLayout.MeasureLayout, staff: Int,
                        system: ScoreLayout.System, colorFor: ((ScoreEvent, Int) -> InkColor)?) -> [DrawItem] {
        var items: [DrawItem] = []
        let clef = score.staves[staff]
        let y = { (step: Int) in layout.y(ofStep: step, staff: staff, system: system.index) }
        let events = measure.events(onStaff: staff)

        // Beam groups decide stem direction for all their notes.
        var groupOf: [Int: Int] = [:]
        var groups: [[Int]] = []
        for (i, e) in events.enumerated() where !e.beams.isEmpty {
            if e.beams[0] == .begin || groups.isEmpty { groups.append([]) }
            groups[groups.count - 1].append(i)
            groupOf[i] = groups.count - 1
        }
        let groupStemUp = groups.map { group -> Bool in
            let all = ScoreEvent(staff: staff, start: 0, duration: 1, type: .eighth, dots: 0, notes: group.flatMap { events[$0].notes })
            return all.stemUp(clef: clef)
        }

        var placed: [Int: Placed] = [:]
        for (i, event) in events.enumerated() {
            guard let x = ml.columns[event.start] else { continue }
            if event.isRest {
                items += rest(event, x: event.isMeasureRest ? ml.x + ml.width / 2 : x, y: y)
                continue
            }
            let up = groupOf[i].map { groupStemUp[$0] } ?? event.stemUp(clef: clef)
            let (noteItems, place) = chord(event, x: x, clef: clef, stemUp: up, y: y,
                                           colorFor: { pitch in colorFor?(event, pitch) ?? .ink })
            items += noteItems
            if let place { placed[i] = place }
        }

        // Stems, flags and beams. A chord whose notes are all played gets a green stem and flag;
        // a beam turns green once every chord under it is played.
        func stemColor(_ i: Int) -> InkColor {
            guard let colorFor, !events[i].notes.isEmpty else { return .ink }
            return events[i].notes.allSatisfy({ colorFor(events[i], $0.midi) == .played }) ? .played : .ink
        }
        for (i, event) in events.enumerated() where event.type.hasStem && !event.isRest {
            guard let p = placed[i], groupOf[i] == nil else { continue }
            let color = stemColor(i)
            items.append(.line(from: DrawPoint(p.stemX, p.noteEndY), to: DrawPoint(p.stemX, p.tipY), width: 0.12 * s, color: color))
            if event.type.flags > 0 {
                let glyph: Glyph = event.type == .eighth ? (p.stemUp ? .flag8thUp : .flag8thDown) : (p.stemUp ? .flag16thUp : .flag16thDown)
                items.append(.glyph(glyph, at: DrawPoint(p.stemX - 0.06 * s, p.tipY), size: s, color: color))
            }
        }
        for (g, group) in groups.enumerated() {
            items += beam(group.compactMap { i in placed[i].map { (i, $0, stemColor(i)) } }, events: events, stemUp: groupStemUp[g])
        }
        return items
    }

    private func rest(_ event: ScoreEvent, x: Double, y: (Int) -> Double) -> [DrawItem] {
        let glyph: Glyph
        var step = 4
        switch event.isMeasureRest ? .whole : event.type {
        case .whole: glyph = .restWhole; step = 6
        case .half: glyph = .restHalf
        case .quarter: glyph = .restQuarter
        case .eighth: glyph = .rest8th
        case .sixteenth: glyph = .rest16th
        }
        var items: [DrawItem] = [.glyph(glyph, at: DrawPoint(x - glyph.width * s / 2, y(step)), size: s, color: .ink)]
        if !event.isMeasureRest {
            for d in 0..<event.dots {
                items.append(.glyph(.augmentationDot, at: DrawPoint(x + glyph.width * s / 2 + (0.4 + Double(d) * 0.5) * s, y(5)), size: s, color: .ink))
            }
        }
        return items
    }

    /// Noteheads, ledger lines, accidentals and dots of one chord; returns where its stem goes.
    private func chord(_ event: ScoreEvent, x: Double, clef: Clef, stemUp: Bool, y: (Int) -> Double,
                       colorFor: (Int) -> InkColor) -> ([DrawItem], Placed?) {
        var items: [DrawItem] = []
        let head: Glyph = event.type == .whole ? .noteheadWhole : (event.type == .half ? .noteheadHalf : .noteheadBlack)
        let headWidth = head.width * s
        let left = x - headWidth / 2

        // Seconds in a chord: every other note of a cluster moves to the far side of the stem.
        let notes = event.notes.sorted { $0.spelled.diatonicIndex < $1.spelled.diatonicIndex }
        let steps = notes.map { clef.staffStep(of: $0.spelled) }
        var shifted = [Bool](repeating: false, count: notes.count)
        if stemUp {
            for i in steps.indices.dropFirst() where steps[i] - steps[i - 1] == 1 && !shifted[i - 1] { shifted[i] = true }
        } else {
            for i in steps.indices.reversed().dropFirst() where steps[i + 1] - steps[i] == 1 && !shifted[i + 1] { shifted[i] = true }
        }
        let shift = (stemUp ? 1.0 : -1.0) * (headWidth - 0.12 * s)

        // Ledger lines span every head on that side of the staff.
        let anyShifted = shifted.contains(true)
        let ledgerLeft = left - 0.4 * s + (anyShifted && !stemUp ? shift : 0)
        let ledgerRight = left + headWidth + 0.4 * s + (anyShifted && stemUp ? shift : 0)
        if let low = steps.min(), low <= -2 {
            for step in stride(from: -2, through: low, by: -2) {
                items.append(.line(from: DrawPoint(ledgerLeft, y(step)), to: DrawPoint(ledgerRight, y(step)), width: 0.16 * s, color: .ink))
            }
        }
        if let high = steps.max(), high >= 10 {
            for step in stride(from: 10, through: high, by: 2) {
                items.append(.line(from: DrawPoint(ledgerLeft, y(step)), to: DrawPoint(ledgerRight, y(step)), width: 0.16 * s, color: .ink))
            }
        }

        var accidentalColumn = 0
        var lastAccidentalStep: Int? = nil
        for (i, note) in notes.enumerated().reversed() { // top down, so accidentals stagger leftwards
            let step = steps[i]
            let headX = left + (shifted[i] ? shift : 0)
            let color = colorFor(note.midi)
            items.append(.glyph(head, at: DrawPoint(headX, y(step)), size: s, color: color))
            if let accidental = note.accidental {
                if let last = lastAccidentalStep, last - step < 6 { accidentalColumn += 1 } else { accidentalColumn = 0 }
                lastAccidentalStep = step
                let glyph: Glyph = accidental > 0 ? .accidentalSharp : (accidental < 0 ? .accidentalFlat : .accidentalNatural)
                let ax = left - (0.3 + Double(accidentalColumn) * 1.2) * s - glyph.width * s
                items.append(.glyph(glyph, at: DrawPoint(ax, y(step)), size: s, color: color))
            }
            for d in 0..<event.dots {
                let dotStep = step % 2 == 0 ? step + 1 : step // dots sit in spaces
                let dx = left + headWidth + (anyShifted && stemUp ? shift : 0) + (0.35 + Double(d) * 0.5) * s
                items.append(.glyph(.augmentationDot, at: DrawPoint(dx, y(dotStep)), size: s, color: color))
            }
        }

        guard event.type.hasStem, let low = steps.min(), let high = steps.max() else { return (items, nil) }
        let middle = y(4)
        if stemUp {
            let stemX = left + headWidth - 0.06 * s
            let tip = min(y(high) - 3.5 * s, middle)
            return (items, Placed(stemX: stemX, stemUp: true, noteEndY: y(low), nearY: y(high), tipY: tip))
        } else {
            let stemX = left + 0.06 * s
            let tip = max(y(low) + 3.5 * s, middle)
            return (items, Placed(stemX: stemX, stemUp: false, noteEndY: y(high), nearY: y(low), tipY: tip))
        }
    }

    /// A beamed group: one straight beam (slope at most half a space), stems cut to it,
    /// and a second beam between neighbouring sixteenths (or a hook for a lone one).
    private func beam(_ members: [(index: Int, place: Placed, color: InkColor)], events: [ScoreEvent], stemUp: Bool) -> [DrawItem] {
        guard let first = members.first, let last = members.last, members.count >= 2 else { return [] }
        var items: [DrawItem] = []
        let x1 = first.place.stemX, x2 = last.place.stemX
        var y1 = first.place.tipY, y2 = last.place.tipY
        let maxRise = 0.5 * s
        if abs(y2 - y1) > maxRise { y2 = y1 + (y2 > y1 ? maxRise : -maxRise) }
        func beamY(_ x: Double) -> Double { x2 == x1 ? y1 : y1 + (y2 - y1) * (x - x1) / (x2 - x1) }
        // Keep every stem at least 2.5 spaces clear of its nearest note.
        var lift = 0.0
        for m in members {
            let deficit = stemUp ? beamY(m.place.stemX) - (m.place.nearY - 2.5 * s)
                                 : (m.place.nearY + 2.5 * s) - beamY(m.place.stemX)
            lift = max(lift, deficit)
        }
        y1 += stemUp ? -lift : lift
        y2 += stemUp ? -lift : lift

        let thickness = 0.5 * s
        let inward = stemUp ? 1.0 : -1.0 // towards the noteheads
        func bar(from a: Double, to b: Double, level: Int, color: InkColor) -> DrawItem {
            let offset = Double(level) * 0.75 * s * inward
            let ya = beamY(a) + offset, yb = beamY(b) + offset
            let t = thickness * inward
            return .shape([.move(DrawPoint(a, ya)), .line(DrawPoint(b, yb)), .line(DrawPoint(b, yb + t)), .line(DrawPoint(a, ya + t)), .close], color: color)
        }
        let allPlayed = members.allSatisfy { $0.color == .played }
        items.append(bar(from: x1 - 0.06 * s, to: x2 + 0.06 * s, level: 0, color: allPlayed ? .played : .ink))
        for (k, m) in members.enumerated() {
            items.append(.line(from: DrawPoint(m.place.stemX, m.place.noteEndY), to: DrawPoint(m.place.stemX, beamY(m.place.stemX)),
                               width: 0.12 * s, color: m.color))
            let beams = events[m.index].beams
            guard beams.count > 1 else { continue }
            switch beams[1] {
            case .begin, .continue:
                if k + 1 < members.count { items.append(bar(from: m.place.stemX, to: members[k + 1].place.stemX, level: 1,
                                                   color: m.color == .played && members[k + 1].color == .played ? .played : .ink)) }
            case .forwardHook:
                items.append(bar(from: m.place.stemX, to: m.place.stemX + 1.1 * s, level: 1, color: m.color))
            case .backwardHook:
                items.append(bar(from: m.place.stemX - 1.1 * s, to: m.place.stemX, level: 1, color: m.color))
            case .end:
                break
            }
        }
        return items
    }

    // MARK: Ties

    /// Curves joining tied notes, including across barlines and onto the next system.
    private func ties() -> [DrawItem] {
        struct Head { var system: Int; var x: Double; var y: Double; var stemUp: Bool }
        var items: [DrawItem] = []
        for (staff, clef) in score.staves.enumerated() {
            // Every notehead on this staff in order: (event start, midi) → position.
            var sequence: [(note: ScoreNote, head: Head)] = []
            for system in layout.systems {
                for ml in system.measures {
                    for event in score.measures[ml.index].events(onStaff: staff) where !event.isRest {
                        guard let x = ml.columns[event.start] else { continue }
                        let up = event.stemUp(clef: clef)
                        for note in event.notes {
                            let y = layout.y(ofStep: clef.staffStep(of: note.spelled), staff: staff, system: system.index)
                            sequence.append((note, Head(system: system.index, x: x, y: y, stemUp: up)))
                        }
                    }
                }
            }
            for (i, entry) in sequence.enumerated() where entry.note.tieStart {
                guard let next = sequence[(i + 1)...].first(where: { $0.note.midi == entry.note.midi && $0.note.tieStop }) else { continue }
                let below = entry.head.stemUp
                if next.head.system == entry.head.system {
                    items.append(tie(from: entry.head.x + 0.7 * s, to: next.head.x - 0.7 * s, y: entry.head.y, below: below))
                } else {
                    let system = layout.systems[entry.head.system]
                    items.append(tie(from: entry.head.x + 0.7 * s, to: system.x + system.width - 0.3 * s, y: entry.head.y, below: below))
                    let nextSystem = layout.systems[next.head.system]
                    items.append(tie(from: nextSystem.x + nextSystem.headerWidth - 0.6 * s, to: next.head.x - 0.7 * s, y: next.head.y, below: below))
                }
            }
        }
        return items
    }

    private func tie(from x1: Double, to x2: Double, y: Double, below: Bool) -> DrawItem {
        let dir = below ? 1.0 : -1.0
        let y0 = y + dir * 0.6 * s
        let height = min(1.2 * s, max(0.5 * s, (x2 - x1) * 0.12))
        let thickness = 0.18 * s
        let c1 = DrawPoint(x1 + (x2 - x1) * 0.25, y0 + dir * height)
        let c2 = DrawPoint(x1 + (x2 - x1) * 0.75, y0 + dir * height)
        let c1i = DrawPoint(c1.x, c1.y - dir * thickness)
        let c2i = DrawPoint(c2.x, c2.y - dir * thickness)
        return .shape([.move(DrawPoint(x1, y0)), .cubic(DrawPoint(x2, y0), control1: c1, control2: c2),
                       .cubic(DrawPoint(x1, y0), control1: c2i, control2: c1i), .close], color: .ink)
    }
}

/// Where the player's fingers are: a see-through circle on the line or space of each held
/// key, with faint ledger lines when it is off the staff. Drawn only while the key is down,
/// so the player sees where they are and corrects it themselves. Used on generated scores
/// and over the printed staff of a book page.
public enum PlayedNoteMarks {
    /// - Parameters:
    ///   - x: centre of the circles (the playhead's column).
    ///   - yOfStep: y in drawing space of a staff step (0 = bottom line, 8 = top line).
    ///   - color: `.playing` (red) for held wrong keys; `.playedMark` (green) over printed notes played correctly.
    ///   - ledgerLines: draw ledger lines off the staff (not needed over a printed note that has its own).
    public static func items(pitches: [Int], key: KeySignature, clef: Clef, x: Double, spacing s: Double,
                             color: InkColor = .playing, ledgerLines: Bool = true,
                             yOfStep: (Int) -> Double) -> [DrawItem] {
        guard !pitches.isEmpty else { return [] }
        let steps = pitches.sorted().map { clef.staffStep(of: key.spell($0)) }
        let diameter = 1.0 * s
        var items: [DrawItem] = []

        // Notes a step apart sit side by side so both stay visible.
        var offsets = [Double](repeating: 0, count: steps.count)
        for i in steps.indices.dropFirst() where steps[i] - steps[i - 1] <= 1 && offsets[i - 1] == 0 {
            offsets[i] = 0.9 * s
        }
        let half = 0.85 * s + (offsets.max() ?? 0) / 2
        let centre = x + (offsets.max() ?? 0) / 2
        if ledgerLines, let low = steps.min(), low <= -2 {
            for ledger in stride(from: -2, through: low, by: -2) {
                items.append(.line(from: DrawPoint(centre - half, yOfStep(ledger)), to: DrawPoint(centre + half, yOfStep(ledger)),
                                   width: 0.14 * s, color: color))
            }
        }
        if ledgerLines, let high = steps.max(), high >= 10 {
            for ledger in stride(from: 10, through: high, by: 2) {
                items.append(.line(from: DrawPoint(centre - half, yOfStep(ledger)), to: DrawPoint(centre + half, yOfStep(ledger)),
                                   width: 0.14 * s, color: color))
            }
        }
        for (i, step) in steps.enumerated() {
            let cx = x + offsets[i]
            items.append(.rect(x: cx - diameter / 2, y: yOfStep(step) - diameter / 2, width: diameter, height: diameter,
                               cornerRadius: diameter / 2, color: color))
        }
        return items
    }
}
