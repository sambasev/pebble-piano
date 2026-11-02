import Foundation
import PianoGraderCore

/// Corrections the learner makes to a bar read wrong: move a note, change its accidental or
/// length, turn it into a rest (or back), add or remove a note, or change a staff's clef.
/// Each changes only what the learner asked: a note that's moved keeps its length, and so on.
/// Out-of-range note indexes are ignored.
extension BarMerge.Bar {
    /// One line or space up (positive) or down. Rests don't move.
    public mutating func move(_ staff: SystemReading.StaffName, _ k: Int, by steps: Int) {
        change(staff, k) { n in
            guard !n.note.rest else { return }
            n.note.position += steps
        }
    }

    /// No accidental → sharp → flat → natural → none again. The natural step is only there when
    /// a sharp or flat earlier in the bar is in force (otherwise a natural changes nothing), and
    /// a natural that cancels nothing counts as none (readings often mark plain notes "natural").
    public mutating func cycleAccidental(_ staff: SystemReading.StaffName, _ k: Int) {
        let shown = shownAccidental(staff, k), cancels = alterInForce(staff, before: k) != 0
        change(staff, k) { n in
            guard !n.note.rest else { return }
            switch shown {
            case .none: n.note.accidental = .sharp
            case .sharp: n.note.accidental = .flat
            case .flat: n.note.accidental = cancels ? .natural : .none
            case .natural: n.note.accidental = .none
            }
        }
    }

    /// The note's accidental as it matters: a natural that cancels no sharp or flat earlier in
    /// the bar changes nothing, so it's `.none`.
    public func shownAccidental(_ staff: SystemReading.StaffName, _ k: Int) -> SystemReading.Accidental {
        let notes = self.notes(staff)
        guard notes.indices.contains(k) else { return .none }
        guard notes[k].note.accidental == .natural else { return notes[k].note.accidental }
        return alterInForce(staff, before: k) != 0 ? .natural : .none
    }

    /// The sharp (+1) or flat (−1) in force on note `k`'s line or space from earlier in the bar.
    func alterInForce(_ staff: SystemReading.StaffName, before k: Int) -> Int {
        let notes = self.notes(staff)
        guard notes.indices.contains(k) else { return 0 }
        var accidentals = BarAccidentals()
        for n in notes[..<k] where !n.note.rest {
            _ = accidentals.play(step: StaffPitch.step(n.clef, n.note.position), accidental: n.note.accidental)
        }
        return accidentals.alter(atStep: StaffPitch.step(notes[k].clef, notes[k].note.position))
    }

    public mutating func setDuration(_ staff: SystemReading.StaffName, _ k: Int, _ duration: SystemReading.Duration) {
        change(staff, k) { $0.note.duration = duration }
    }

    public mutating func toggleDot(_ staff: SystemReading.StaffName, _ k: Int) {
        change(staff, k) { $0.note.dotted.toggle() }
    }

    /// A note becomes a rest of the same length, and back (on the line or space it had).
    public mutating func toggleRest(_ staff: SystemReading.StaffName, _ k: Int) {
        change(staff, k) { n in
            n.note.rest.toggle()
            if n.note.rest {
                n.note.accidental = .none
                n.note.finger = nil
            }
        }
    }

    /// Adds a note after note `k` (at the start when `k` is nil): a copy of its neighbour (the
    /// note before it, else the first), without accidental or finger, so it's one click from
    /// right. On an empty staff, a quarter on the middle line in `clef`. Returns its index.
    @discardableResult
    public mutating func insertNote(_ staff: SystemReading.StaffName, after k: Int?,
                                    clef: SystemReading.Clef) -> Int {
        var notes = self.notes(staff)
        let at = k.map { min(max($0 + 1, 0), notes.count) } ?? 0
        let model = notes.indices.contains(at - 1) ? notes[at - 1] : notes.first
        var note = model.map { BarMerge.Note(note: $0.note, clef: $0.clef) }
            ?? BarMerge.Note(note: .init(position: 4, duration: .quarter), clef: clef)
        note.note.accidental = .none
        note.note.finger = nil
        notes.insert(note, at: at)
        setNotes(staff, notes)
        return at
    }

    public mutating func deleteNote(_ staff: SystemReading.StaffName, _ k: Int) {
        var notes = self.notes(staff)
        guard notes.indices.contains(k) else { return }
        notes.remove(at: k)
        setNotes(staff, notes)
    }

    /// Reads the staff in another clef: the notes keep their lines and spaces, so they sound
    /// different.
    public mutating func setClef(_ staff: SystemReading.StaffName, _ clef: SystemReading.Clef) {
        setNotes(staff, notes(staff).map { var n = $0; n.clef = clef; return n })
    }

    /// The staff's clef: its notes', else `fallback`.
    public func clef(_ staff: SystemReading.StaffName, fallback: SystemReading.Clef) -> SystemReading.Clef {
        notes(staff).first?.clef ?? fallback
    }

    /// How long the staff's notes and rests last, in quarter notes.
    public func quarters(_ staff: SystemReading.StaffName) -> Double {
        notes(staff).reduce(0) { $0 + $1.note.quarters }
    }

    private mutating func change(_ staff: SystemReading.StaffName, _ k: Int, _ edit: (inout BarMerge.Note) -> Void) {
        var notes = self.notes(staff)
        guard notes.indices.contains(k) else { return }
        edit(&notes[k])
        notes[k].head = nil  // no longer the measured note
        setNotes(staff, notes)
    }

    private mutating func setNotes(_ staff: SystemReading.StaffName, _ notes: [BarMerge.Note]) {
        if staff == .upper { upper = notes } else { lower = notes }
    }
}

extension ScoreWriter {
    /// The metre the piece will be written in (see `write`): what each bar should add up to.
    public static func metre(of bars: [BarMerge.Bar]) -> TimeSignature { timeSignature(of: bars) }
}
