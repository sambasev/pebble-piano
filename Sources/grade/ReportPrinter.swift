import Foundation
import PianoGraderCore

enum ReportPrinter {
    static func json(_ report: GradeReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    static func text(_ report: GradeReport, rubric: Rubric, reference: URL, take: URL) -> String {
        var lines: [String] = []
        lines.append("\(report.passed ? "PASS" : "FAIL")  \(rubric.level)  \(reference.lastPathComponent) ← \(take.lastPathComponent)")

        for level in report.levels {
            let mark: String
            switch level.passed {
            case .some(true): mark = "✓"
            case .some(false): mark = "✗"
            case .none: mark = "–"
            }
            let name = level.check.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            var line = "  \(name) \(mark)  \(level.detail)"
            if level.passed == nil {
                line += "  (not graded)"
            } else {
                switch level.check {
                case .notes: line += "  need ≥ \(percent(rubric.notes.minAccuracy))"
                case .rhythm: line += "  need ≤ \(percent(rubric.rhythm.maxMeanIOIError))"
                case .tempo: line += "  need ±\(percent(rubric.tempo.tolerance))"
                }
            }
            lines.append(line)
        }

        let n = report.notes
        if n.ignoredLeading + n.ignoredTrailing > 0 {
            lines.append("  (ignored \(n.ignoredLeading) note(s) before and \(n.ignoredTrailing) after the passage)")
        }

        if report.flags.isEmpty {
            lines.append("No mistakes flagged.")
        } else {
            lines.append("Flags:")
            for f in report.flags { lines.append("  \(f.message)") }
        }
        return lines.joined(separator: "\n")
    }

    static func percent(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
}
