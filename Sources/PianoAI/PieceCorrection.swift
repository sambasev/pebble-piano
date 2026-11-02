import Foundation

/// A piece read from a book as the learner checked and corrected it: each line's reading and
/// measurements, and every bar as it stands now and as first read. Saved with the piece, so
/// checking it again reopens it exactly as it was left, without reading anything again.
/// The score, MIDI and MusicXML are made from `bars` each time the piece is saved.
public struct PieceCorrection: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    /// Where a bar's check stands.
    public enum Resolution: String, Codable, Sendable {
        /// The measured pitches agreed with the reading: nothing to check.
        case trusted
        /// To check.
        case needsReview
        /// The learner said it's right as read.
        case confirmed
        /// Read again on its own, and the measurements agreed.
        case fixed
        /// The learner moved its notes.
        case nudged
    }

    /// One line as read: a system, or one staff of it when the right hand plays both staves.
    public struct Line: Codable, Equatable, Sendable {
        public var found: FoundSystem
        /// One staff of the line on its own (right hand only), not a pair.
        public var singleStaff: Bool
        public var reading: SystemReading?
        public var geometry: NoteheadGeometry.System?

        public init(found: FoundSystem, singleStaff: Bool, reading: SystemReading?, geometry: NoteheadGeometry.System?) {
            self.found = found
            self.singleStaff = singleStaff
            self.reading = reading
            self.geometry = geometry
        }
    }

    public struct Bar: Codable, Equatable, Sendable {
        /// Which of `lines` it's in.
        public var line: Int
        /// As it stands: corrected, read again, or as first read.
        public var bar: BarMerge.Bar
        /// As the first reading had it.
        public var original: BarMerge.Bar
        public var resolution: Resolution

        public init(line: Int, bar: BarMerge.Bar, original: BarMerge.Bar, resolution: Resolution) {
            self.line = line
            self.bar = bar
            self.original = original
            self.resolution = resolution
        }
    }

    public var version: Int
    /// A right-hand piece, written on one staff.
    public var oneStaff: Bool
    public var lines: [Line]
    /// The piece's bars in order.
    public var bars: [Bar]

    public init(oneStaff: Bool, lines: [Line], bars: [Bar]) {
        version = Self.currentVersion
        self.oneStaff = oneStaff
        self.lines = lines
        self.bars = bars
    }

    /// Bars pointing at a line that isn't there would crash the review: the file is unusable.
    public var isConsistent: Bool {
        version <= Self.currentVersion && bars.allSatisfy { lines.indices.contains($0.line) }
    }
}
