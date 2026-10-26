import Foundation

/// Turns a MIDI sequence into a written piano score.
///
/// - Positions come from the file's ticks (quarter notes), snapped to a sixteenth-note grid.
/// - Hands: a file with two tracks (or, in one track, two channels) puts the higher one on the
///   treble staff and the other on the bass staff. Otherwise notes from middle C up go on the
///   treble staff and the rest on the bass staff; music that fits one clef gets one staff.
/// - The key comes from the file's key signature, or is estimated from the notes.
/// - Each staff is one voice of chords: a note held past the next onset on its staff is cut
///   at that onset. Notes that cross a barline, or need a length no single value can show,
///   are split and tied.
/// - Drums (channel 10) are left out.
public struct Transcriber {
    public var options: Options

    public struct Options: Sendable {
        /// Notes from this pitch up go on the treble staff when hands are split by pitch.
        public var splitPitch = 60
        /// Override the key signature (otherwise from the file, then estimated).
        public var key: KeySignature?

        public init(splitPitch: Int = 60, key: KeySignature? = nil) {
            self.splitPitch = splitPitch
            self.key = key
        }
    }

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Sixteenth-note values a single written note can show, longest first: (length, type, dots).
    static let values: [(Int, NoteType, Int)] = [
        (16, .whole, 0), (12, .half, 1), (8, .half, 0), (6, .quarter, 1),
        (4, .quarter, 0), (3, .eighth, 1), (2, .eighth, 0), (1, .sixteenth, 0),
    ]

    public func transcribe(_ sequence: MIDISequence, title: String? = nil) -> Score {
        let ts = sequence.timeSignature
        let measureLength = max(1, Int((ts.quartersPerMeasure * Double(Score.sixteenthsPerQuarter)).rounded()))
        let secondsPerQuarter = 60.0 / max(1, sequence.initialTempoBPM)

        // 1. Quantize. Drums are not notation.
        struct Q { var pitch: Int; var start: Int; var end: Int; var track: Int; var channel: Int }
        var notes: [Q] = []
        for n in sequence.notes where n.channel != 9 {
            let onBeats = n.onsetBeats
            let offBeats = n.offsetBeats ?? (onBeats + (n.offset - n.onset) / secondsPerQuarter)
            let start = max(0, Int((onBeats * Double(Score.sixteenthsPerQuarter)).rounded()))
            let end = max(start + 1, Int((offBeats * Double(Score.sixteenthsPerQuarter)).rounded()))
            notes.append(Q(pitch: n.pitch, start: start, end: end, track: n.track, channel: n.channel))
        }

        let key = options.key ?? sequence.keySignature ?? KeySignature.estimate(from: sequence.notes.filter { $0.channel != 9 })
        let name = title ?? sequence.title ?? "Untitled"

        guard !notes.isEmpty else {
            let rest = ScoreEvent(staff: 0, start: 0, duration: measureLength, type: .whole, dots: 0, notes: [], isMeasureRest: true)
            return Score(title: name, tempoBPM: sequence.initialTempoBPM, timeSignature: ts, key: key, staves: [.treble],
                         measures: [ScoreMeasure(number: 1, startSixteenth: 0, length: measureLength, events: [rest])])
        }

        // 2. Hands and staves.
        let byTrack = Dictionary(grouping: notes, by: \.track)
        let byChannel = Dictionary(grouping: notes, by: \.channel)
        let groups: [Int: [Q]]? = byTrack.count == 2 ? byTrack : (byTrack.count == 1 && byChannel.count == 2 ? byChannel : nil)
        let useTracks = byTrack.count == 2
        var staves: [Clef]
        var staffOf: (Q) -> Int
        if let groups {
            let mean = groups.mapValues { qs in Double(qs.map(\.pitch).reduce(0, +)) / Double(qs.count) }
            let upper = mean.max { $0.value < $1.value }!.key
            staves = [.treble, .bass]
            staffOf = { q in (useTracks ? q.track : q.channel) == upper ? 0 : 1 }
        } else {
            let low = notes.map(\.pitch).min()!, high = notes.map(\.pitch).max()!
            let split = options.splitPitch
            if low >= split - 5 {
                staves = [.treble]
                staffOf = { _ in 0 }
            } else if high <= split + 4 {
                staves = [.bass]
                staffOf = { _ in 0 }
            } else {
                staves = [.treble, .bass]
                staffOf = { q in q.pitch >= split ? 0 : 1 }
            }
        }

        let lastEnd = notes.map(\.end).max()!
        let measureCount = max(1, (lastEnd + measureLength - 1) / measureLength)
        let total = measureCount * measureLength

        // 3. Each staff becomes a timeline of chords and rests, then written values per measure.
        var eventsByMeasure = [[ScoreEvent]](repeating: [], count: measureCount)
        for staff in staves.indices {
            var chords: [Int: (pitches: Set<Int>, end: Int)] = [:]
            for q in notes where staffOf(q) == staff {
                var c = chords[q.start] ?? ([], q.start + 1)
                c.pitches.insert(q.pitch)
                c.end = max(c.end, q.end)
                chords[q.start] = c
            }
            let starts = chords.keys.sorted()
            var segments: [(start: Int, end: Int, pitches: [Int])] = []
            var cursor = 0
            for (i, start) in starts.enumerated() {
                if start > cursor { segments.append((cursor, start, [])) }
                let next = i + 1 < starts.count ? starts[i + 1] : total
                let end = min(chords[start]!.end, next)
                segments.append((start, end, chords[start]!.pitches.sorted()))
                cursor = end
            }
            if cursor < total { segments.append((cursor, total, [])) }

            for seg in segments {
                // Split at barlines; chord pieces are tied together.
                var pieces: [(measure: Int, start: Int, length: Int)] = []
                var position = seg.start
                while position < seg.end {
                    let m = position / measureLength
                    let barEnd = (m + 1) * measureLength
                    let pieceEnd = min(seg.end, barEnd)
                    for (offset, length) in Self.split(start: position - m * measureLength, length: pieceEnd - position) {
                        pieces.append((m, offset, length))
                    }
                    position = pieceEnd
                }
                for (i, piece) in pieces.enumerated() {
                    let (type, dots) = Self.value(for: piece.length)
                    let written = seg.pitches.map { midi in
                        ScoreNote(midi: midi, spelled: key.spell(midi),
                                  tieStart: i < pieces.count - 1, tieStop: i > 0)
                    }
                    eventsByMeasure[piece.measure].append(
                        ScoreEvent(staff: staff, start: piece.start, duration: piece.length, type: type, dots: dots, notes: written))
                }
            }
        }

        // 4. Whole-measure rests, ordering and accidentals.
        var measures: [ScoreMeasure] = []
        for m in 0..<measureCount {
            var events: [ScoreEvent] = []
            for staff in staves.indices {
                var staffEvents = eventsByMeasure[m].filter { $0.staff == staff }.sorted { $0.start < $1.start }
                if staffEvents.allSatisfy(\.isRest) {
                    staffEvents = [ScoreEvent(staff: staff, start: 0, duration: measureLength, type: .whole, dots: 0,
                                              notes: [], isMeasureRest: true)]
                } else {
                    staffEvents = Self.mergeRests(staffEvents)
                }
                Self.assignAccidentals(&staffEvents, key: key)
                Self.assignBeams(&staffEvents, beatLength: Self.beamGroupLength(ts))
                events += staffEvents
            }
            measures.append(ScoreMeasure(number: m + 1, startSixteenth: m * measureLength, length: measureLength, events: events))
        }

        return Score(title: name, tempoBPM: sequence.initialTempoBPM, timeSignature: ts, key: key,
                     staves: staves, measures: measures)
    }

    /// Splits a span inside one measure into lengths single written values can show,
    /// longest first, keeping each value on a position it reads naturally from:
    /// halves and longer start on a beat, quarters on an eighth, eighths on a sixteenth.
    static func split(start: Int, length: Int) -> [(start: Int, length: Int)] {
        var result: [(Int, Int)] = []
        var position = start
        var remaining = length
        while remaining > 0 {
            let fit = values.first { value in
                let (len, type, _) = value
                guard len <= remaining else { return false }
                let alignment = type == .quarter ? 2 : min(type.sixteenths, 4)
                return position % alignment == 0
            }
            let len = fit?.0 ?? 1
            result.append((position, len))
            position += len
            remaining -= len
        }
        return result
    }

    static func value(for length: Int) -> (NoteType, Int) {
        let match = values.first { $0.0 == length }
        return match.map { ($0.1, $0.2) } ?? (.sixteenth, 0)
    }

    /// Joins neighbouring rests left by splitting so a gap reads as few rests as possible.
    static func mergeRests(_ events: [ScoreEvent]) -> [ScoreEvent] {
        var result: [ScoreEvent] = []
        var i = 0
        while i < events.count {
            guard events[i].isRest else { result.append(events[i]); i += 1; continue }
            var j = i
            var end = events[i].start + events[i].duration
            while j + 1 < events.count, events[j + 1].isRest, events[j + 1].start == end {
                j += 1
                end = events[j].start + events[j].duration
            }
            for (start, length) in split(start: events[i].start, length: end - events[i].start) {
                let (type, dots) = value(for: length)
                result.append(ScoreEvent(staff: events[i].staff, start: start, duration: length, type: type, dots: dots, notes: []))
            }
            i = j + 1
        }
        return result
    }

    /// Beam groups: a dotted quarter in compound metres (6/8, 9/8, 12/8), otherwise a quarter.
    static func beamGroupLength(_ ts: TimeSignature) -> Int {
        ts.denominator == 8 && ts.numerator % 3 == 0 && ts.numerator > 3 ? 6 : 4
    }

    /// Beams consecutive eighths and sixteenths that fall inside one beat. A sixteenth next
    /// to another gets a second beam; a lone sixteenth in a group gets a hook.
    static func assignBeams(_ events: inout [ScoreEvent], beatLength: Int) {
        func beamable(_ e: ScoreEvent) -> Bool {
            !e.isRest && (e.type == .eighth || e.type == .sixteenth)
                && e.start / beatLength == (e.start + e.duration - 1) / beatLength
        }
        var i = 0
        while i < events.count {
            guard beamable(events[i]) else { i += 1; continue }
            var run = [i]
            while let last = run.last, last + 1 < events.count, beamable(events[last + 1]),
                  events[last + 1].start == events[last].start + events[last].duration,
                  events[last + 1].start / beatLength == events[i].start / beatLength {
                run.append(last + 1)
            }
            if run.count >= 2 {
                for (k, index) in run.enumerated() {
                    var beams: [Beam] = [k == 0 ? .begin : (k == run.count - 1 ? .end : .continue)]
                    if events[index].type == .sixteenth {
                        let prev = k > 0 && events[run[k - 1]].type == .sixteenth
                        let next = k < run.count - 1 && events[run[k + 1]].type == .sixteenth
                        switch (prev, next) {
                        case (true, true): beams.append(.continue)
                        case (true, false): beams.append(.end)
                        case (false, true): beams.append(.begin)
                        case (false, false): beams.append(k == 0 ? .forwardHook : .backwardHook)
                        }
                    }
                    events[index].beams = beams
                }
            }
            i = run.last! + 1
        }
    }

    /// Prints an accidental where a note differs from the key signature or from an earlier
    /// accidental on the same line or space in the measure. A tied continuation prints none.
    static func assignAccidentals(_ events: inout [ScoreEvent], key: KeySignature) {
        var current: [Int: Int] = [:] // diatonic index → alteration in force
        for e in events.indices {
            for n in events[e].notes.indices {
                let spelled = events[e].notes[n].spelled
                let inForce = current[spelled.diatonicIndex] ?? key.alter(forStep: spelled.step)
                if spelled.alter != inForce && !events[e].notes[n].tieStop {
                    events[e].notes[n].accidental = spelled.alter
                }
                current[spelled.diatonicIndex] = spelled.alter
            }
        }
    }
}
