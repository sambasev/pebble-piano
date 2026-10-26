import Foundation

/// A rectangle in PDF page space: points, origin at the bottom-left of the page
/// (the same space PDFKit uses), so boxes can be measured straight from the PDF.
public struct PageRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Smallest rectangle containing both.
    public func union(_ other: PageRect) -> PageRect {
        let x0 = min(x, other.x), y0 = min(y, other.y)
        return PageRect(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }

    public func insetBy(dx: Double, dy: Double) -> PageRect {
        PageRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
}

/// One printed measure of a passage.
public struct MeasureAnnotation: Codable, Equatable, Sendable {
    /// Printed measure number within the passage, from 1.
    public var number: Int
    /// Length in quarter notes (4 for a 4/4 bar).
    public var quarters: Double
    /// Region of the page the measure occupies, staff plus stems and note heads.
    public var box: PageRect
    /// Horizontal positions of the measure's first beat and of the point one full
    /// measure later, so the playhead can move linearly between them.
    public var beatX: [Double]
    /// The measure's staff lines. Optional: when absent, PianoPad finds them in the page image.
    public var staff: StaffPlacement?

    public init(number: Int, quarters: Double, box: PageRect, beatX: [Double], staff: StaffPlacement? = nil) {
        self.number = number
        self.quarters = quarters
        self.box = box
        self.beatX = beatX
        self.staff = staff
    }

    /// x position at a fraction (0–1) of the way through the measure, kept inside the box.
    public func x(atFraction fraction: Double) -> Double {
        let start = beatX.first ?? box.x
        let end = beatX.count > 1 ? beatX[1] : box.maxX
        let x = start + (end - start) * max(0, min(1, fraction))
        return min(max(x, box.x), box.maxX)
    }
}

/// A passage on a page: what to play, where it is printed, and how to grade it.
public struct PassageAnnotation: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Page number, from 1.
    public var page: Int
    /// Reference MIDI, relative to the annotations file.
    public var reference: String
    /// Rubric preset name ("beginner", "intermediate") or a rubric file relative to the annotations file.
    public var rubric: String?
    /// Short instruction from the book, shown above the score.
    public var instructions: String?
    /// Whole passage region on the page.
    public var box: PageRect
    public var measures: [MeasureAnnotation]
    /// Printed measure numbers in the order they are played, so repeats map back to
    /// the right place on the page. Defaults to each measure once, in order.
    public var playOrder: [Int]?
    /// Clef of the printed staff. Defaults to treble.
    public var clef: Clef?
    /// A recorded backing track to play along with.
    public var backing: BackingAnnotation?

    public init(id: String, title: String, page: Int, reference: String, rubric: String? = nil,
                instructions: String? = nil, box: PageRect, measures: [MeasureAnnotation], playOrder: [Int]? = nil,
                clef: Clef? = nil, backing: BackingAnnotation? = nil) {
        self.id = id
        self.title = title
        self.page = page
        self.reference = reference
        self.rubric = rubric
        self.instructions = instructions
        self.box = box
        self.measures = measures
        self.playOrder = playOrder
        self.clef = clef
        self.backing = backing
    }

    /// Length of each bar in quarters, in played order (repeats written out).
    public var playedBarLengths: [Double] { order.compactMap { measure($0)?.quarters } }

    public var order: [Int] { playOrder ?? measures.map(\.number) }

    public func measure(_ number: Int) -> MeasureAnnotation? {
        measures.first { $0.number == number }
    }

    /// Where a point in the performance (quarter notes from the start of the reference)
    /// falls on the page. nil before the start or after the end.
    public func location(atQuarter quarter: Double) -> (measure: MeasureAnnotation, fraction: Double, x: Double)? {
        guard quarter >= 0 else { return nil }
        var start = 0.0
        for number in order {
            guard let m = measure(number) else { continue }
            if quarter < start + m.quarters {
                let fraction = (quarter - start) / m.quarters
                return (m, fraction, m.x(atFraction: fraction))
            }
            start += m.quarters
        }
        return nil
    }

    /// Which time through the printed music a point in the performance is: 0 the first time,
    /// 1 after the first jump back (a repeat), and so on. nil outside the passage.
    public func lap(atQuarter quarter: Double) -> Int? {
        guard quarter >= 0 else { return nil }
        var start = 0.0
        var lap = 0
        var previous: Int? = nil
        for number in order {
            guard let m = measure(number) else { continue }
            if let previous, number <= previous { lap += 1 }
            previous = number
            if quarter < start + m.quarters { return lap }
            start += m.quarters
        }
        return nil
    }

    /// Printed measure for the nth measure played (1-based), as the grader numbers
    /// measures from the start of the reference.
    public func printedMeasure(forPlayed ordinal: Int) -> Int? {
        let order = order
        guard ordinal >= 1, ordinal <= order.count else { return nil }
        return order[ordinal - 1]
    }

    /// Printed measures where the grade report flags at least one mistake.
    public func measuresWithMistakes(in report: GradeReport) -> Set<Int> {
        Set(report.flags.compactMap { printedMeasure(forPlayed: $0.position.measure) })
    }
}

/// All the annotated passages of one book.
public struct BookAnnotations: Codable, Equatable, Sendable {
    public var title: String
    /// The book's PDF, relative to the annotations file.
    public var pdf: String
    public var license: String?
    public var passages: [PassageAnnotation]

    public init(title: String, pdf: String, license: String? = nil, passages: [PassageAnnotation]) {
        self.title = title
        self.pdf = pdf
        self.license = license
        self.passages = passages
    }

    public static func load(url: URL) throws -> BookAnnotations {
        try JSONDecoder().decode(BookAnnotations.self, from: Data(contentsOf: url))
    }
}
