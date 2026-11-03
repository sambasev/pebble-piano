#if os(macOS)
import Charts
import PianoGraderCore
import PianoLessons
import PianoPadState
import SwiftUI

// The progress overview: a learner's takes, mistakes by kind and tempo over time, what is
// improving, and where the mistakes keep happening. Opened from the learner menu.

extension MistakeTally.Category {
    /// Chart colour. Charts always pair it with the category's name (legend, labels).
    var color: Color {
        switch self {
        case .pitch: PP.mistake
        case .missed: PP.apricot
        case .extra: PP.lilac
        case .timing: PP.accent
        case .tempo: PP.mint
        }
    }

    var symbol: String {
        switch self {
        case .pitch: "pianokeys"
        case .missed: "circle.dashed"
        case .extra: "plus.circle"
        case .timing: "metronome"
        case .tempo: "speedometer"
        }
    }
}

extension PlaySession {
    /// A readable name for a piece in the learner's history.
    func overviewName(for piece: PieceID, settings: LearnerSettings?) -> String {
        let raw = piece.rawValue
        if raw.hasPrefix("lesson:") {
            let parts = raw.dropFirst("lesson:".count).split(separator: "/").map(String.init)
            guard let unitID = parts.first else { return "Lesson" }
            let pageID = parts.count > 1 ? parts[1] : ""
            if let unit = lessonRunner.unit?.unit, unit.id == unitID,
               let page = unit.pages.first(where: { $0.id == pageID }) {
                return page.title
            }
            if unitID == PieceLessonBuilder.unitID,
               let mine = PieceLessonStore.pages().first(where: { $0.page.id == pageID }) {
                return mine.page.title
            }
            return "Lesson " + pageID.replacingOccurrences(of: "-", with: " ")
        }
        if raw.hasPrefix("passage:") {
            let rest = raw.dropFirst("passage:".count)
            let bookAndID = rest.split(separator: "#", maxSplits: 1).map(String.init)
            if bookAndID.count == 2, let book, book.annotations.pdf == bookAndID[0],
               let passage = book.annotations.passages.first(where: { $0.id == bookAndID[1] }) {
                return passage.title
            }
            let bookName = (bookAndID.first.map { ($0 as NSString).deletingPathExtension } ?? "Book")
            return bookAndID.count == 2 ? "\(bookName) · \(bookAndID[1])" : bookName
        }
        if let recent = settings?.recentPieces.first(where: { $0.id == piece }) {
            if let title = recent.title { return title }
            if let path = recent.path { return (path as NSString).lastPathComponent }
        }
        return "MIDI piece"
    }
}

struct StudentOverviewView: View {
    @EnvironmentObject var session: PlaySession
    let learner: Learner
    var onDone: () -> Void

    @State private var range: StudentOverview.Range = .month
    @State private var allTakes: [StudentOverview.Take]?
    @State private var sessions: [PracticeSession] = []
    @State private var settings: LearnerSettings?
    @State private var tutorLessons: [TutorLessonProgress] = []

    private var overview: StudentOverview? {
        allTakes.map { StudentOverview.build(takes: $0, sessions: sessions, range: range) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(PP.Space.s6)
            Divider()
            Group {
                if let overview {
                    if overview.takes.isEmpty && overview.minutes == 0 && tutorLessons.isEmpty {
                        empty
                    } else {
                        ScrollView {
                            StudentOverviewContent(overview: overview, tutorLessons: tutorLessons) {
                                session.overviewName(for: $0, settings: settings)
                            }
                                .padding(PP.Space.s6)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 760)
        .foregroundColor(PP.ink)
        .task(id: learner.id) { await load() }
    }

    private func load() async {
        let history = session.learnerStore.history(for: learner.id)
        settings = session.learnerStore.settings(for: learner.id)
        let learnerKey = learner.id.uuidString
        let (takes, sessions, tutorLessons) = await Task.detached(priority: .userInitiated) {
            (history.overviewTakes(), history.sessions(), TutorLessonProgress.load(learner: learnerKey))
        }.value
        self.sessions = sessions
        self.tutorLessons = tutorLessons
        allTakes = takes
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: PP.Space.s3) {
            LearnerAvatar(learner: learner, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(learner.name)'s progress").font(.ppHeadline)
                Text("Lessons played and mistakes made over time").font(.ppCaption).foregroundColor(PP.inkMuted)
            }
            Spacer()
            PPSegmented(selection: $range, StudentOverview.Range.allCases.map { ($0, $0.title) })
                .accessibilityLabel("Range")
                .fixedSize()
            Button("Done", action: onDone)
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var empty: some View {
        VStack(spacing: PP.Space.s3) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundColor(PP.inkStaff)
            Text(range == .all ? "No graded takes yet" : "Nothing played in the last \(range.title)")
                .font(.ppHeadline)
            Text("Play a lesson or a piece through to the end and it shows up here.")
                .font(.ppCallout).foregroundColor(PP.inkMuted)
            if range != .all {
                Button("Show all time") { range = .all }.buttonStyle(PPGlassButtonStyle())
            }
        }
    }

}

/// The overview's tiles, charts and lists for one range.
struct StudentOverviewContent: View {
    let overview: StudentOverview
    /// Pieces under way with the AI tutor (not limited to the range: it's where they stand now).
    var tutorLessons: [TutorLessonProgress] = []
    /// A readable name for a piece.
    let pieceName: (PieceID) -> String

    var body: some View { content(overview) }

    private func content(_ o: StudentOverview) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s6) {
            tiles(o)
            if let focus = o.focus { focusCard(focus) }
            section("Takes played", caption: "Each graded attempt at a lesson or a piece") { activityChart(o) }
            if !tutorLessons.isEmpty {
                section("Learning with the AI tutor", caption: "Imported pieces and how far through each lesson plan") { tutorProgress }
            }
            section("Mistakes per 100 notes", caption: "Shorter bars are better") { mistakesChart(o) }
            if !o.trends.isEmpty {
                section("Earlier vs. lately", caption: "The first half of these takes against the second half") { trends(o) }
            }
            section("Tempo", caption: "How far each day's takes ran from the set speed. The band is ±\(Int(MistakeTally.tempoTolerance * 100))%.") {
                tempoChart(o)
            }
            section("Score", caption: "Average share of notes right, after extra-note penalties") { scoreChart(o) }
            if !o.troubleSpots.isEmpty {
                section("Trouble spots", caption: "Bars with mistakes in two or more takes") { troubleSpots(o) }
            }
            if !o.pieces.isEmpty {
                section("Pieces", caption: nil) { pieces(o) }
            }
        }
    }

    private func section<Content: View>(_ title: String, caption: String?, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text(title).ppEyebrow()
            if let caption { Text(caption).font(.ppCaption).foregroundColor(PP.inkMuted) }
            body()
        }
        .padding(PP.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PP.Radius.md).fill(PP.surfaceRaised))
    }

    private func tiles(_ o: StudentOverview) -> some View {
        HStack(spacing: PP.Space.s3) {
            tile("Takes", "\(o.takes.count)", detail: "\(o.passes) passed")
            tile("Practice", o.minutes >= 60 ? String(format: "%.1f h", Double(o.minutes) / 60) : "\(o.minutes) min",
                 detail: o.tutorMinutes > 0 ? "\(o.tutorMinutes) min with the AI tutor"
                    : "\(o.pagesCompleted) lesson page\(o.pagesCompleted == 1 ? "" : "s") finished")
            tile("Average score", o.averageScore.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", detail: scoreDetail(o))
            tile("Mistakes", "\(o.totals.noteMistakes)",
                 detail: o.totals.expected > 0
                    ? String(format: "%.1f per 100 notes", 100 * Double(o.totals.noteMistakes) / Double(o.totals.expected))
                    : "")
        }
    }

    private func scoreDetail(_ o: StudentOverview) -> String {
        guard o.takes.count >= StudentOverview.minTakesForTrend else { return "" }
        let half = o.takes.count / 2
        let early = o.takes[..<half].map(\.score).reduce(0, +) / Double(half)
        let late = o.takes[half...].map(\.score).reduce(0, +) / Double(o.takes.count - half)
        let points = Int(((late - early) * 100).rounded())
        return points == 0 ? "steady lately" : "\(points > 0 ? "up" : "down") \(abs(points)) points lately"
    }

    private func tile(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s1) {
            Text(title).ppEyebrow()
            Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit()
            Text(detail).font(.ppCaption).foregroundColor(PP.inkMuted).lineLimit(1)
        }
        .padding(PP.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PP.Radius.md).fill(PP.surfaceRaised))
    }

    private func focusCard(_ focus: StudentOverview.Trend) -> some View {
        HStack(alignment: .top, spacing: PP.Space.s3) {
            Image(systemName: focus.category.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(PP.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(PP.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Work on next: \(focus.category.title.lowercased())").font(.ppHeadline)
                Text("\(focus.category.explanation). Lately \(rateText(focus.category, focus.recent))\(changeText(focus)).")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
        }
        .padding(PP.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PP.Radius.md).strokeBorder(PP.accent, lineWidth: 2))
    }

    private func rateText(_ category: MistakeTally.Category, _ rate: Double) -> String {
        category == .tempo ? "\(Int(rate.rounded()))% of takes" : String(format: "%.1f per 100 notes", rate)
    }

    private func changeText(_ t: StudentOverview.Trend) -> String {
        guard let change = t.change, abs(change) >= 0.05 else { return "" }
        return ", \(change < 0 ? "down" : "up") from \(rateText(t.category, t.earlier))"
    }

    // MARK: Charts

    private func activityChart(_ o: StudentOverview) -> some View {
        Chart {
            ForEach(o.buckets) { b in
                if b.lessonTakes > 0 {
                    BarMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Takes", b.lessonTakes))
                        .foregroundStyle(by: .value("Kind", "Lessons"))
                }
                if b.tutorTakes > 0 {
                    BarMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Takes", b.tutorTakes))
                        .foregroundStyle(by: .value("Kind", "AI tutor"))
                }
                if b.otherTakes > 0 {
                    BarMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Takes", b.otherTakes))
                        .foregroundStyle(by: .value("Kind", "Own pieces and books"))
                }
            }
        }
        .chartForegroundStyleScale(["Lessons": PP.accent, "AI tutor": PP.apricot, "Own pieces and books": PP.lilac])
        .chartXScale(domain: o.domain)
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 150)
    }

    private static let noteCategories: [MistakeTally.Category] = [.pitch, .missed, .extra, .timing]

    private func mistakesChart(_ o: StudentOverview) -> some View {
        Chart {
            ForEach(o.buckets) { b in
                ForEach(Self.noteCategories) { c in
                    BarMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Per 100 notes", b.rate(c)))
                        .foregroundStyle(by: .value("Mistake", c.title))
                }
            }
        }
        .chartForegroundStyleScale(domain: Self.noteCategories.map(\.title), range: Self.noteCategories.map(\.color))
        .chartXScale(domain: o.domain)
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 200)
    }

    private func tempoChart(_ o: StudentOverview) -> some View {
        let points = o.buckets.compactMap { b in b.averageTempoDeviation.map { (b.start, $0 * 100) } }
        let tolerance = MistakeTally.tempoTolerance * 100
        let limit = max(tolerance * 2, (points.map { abs($0.1) }.max() ?? 0) + 5)
        return Group {
            if points.isEmpty {
                Text("No take long enough to measure a tempo yet.").font(.ppCallout).foregroundColor(PP.inkMuted)
            } else {
                Chart {
                    RectangleMark(xStart: .value("Start", o.domain.lowerBound), xEnd: .value("End", o.domain.upperBound),
                                  yStart: .value("Low", -tolerance), yEnd: .value("High", tolerance))
                        .foregroundStyle(PP.success.opacity(0.12))
                    RuleMark(y: .value("On tempo", 0)).foregroundStyle(PP.inkStaff)
                    ForEach(points, id: \.0) { date, deviation in
                        LineMark(x: .value("Day", date, unit: o.bucketUnit), y: .value("Off tempo (%)", deviation))
                            .foregroundStyle(PP.mint)
                        PointMark(x: .value("Day", date, unit: o.bucketUnit), y: .value("Off tempo (%)", deviation))
                            .foregroundStyle(abs(deviation) > tolerance ? PP.warning : PP.success)
                            .symbol(abs(deviation) > tolerance ? .triangle : .circle)
                    }
                }
                .chartXScale(domain: o.domain)
                .chartYScale(domain: -limit...limit)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v > 0 ? "+\(Int(v))% fast" : v < 0 ? "\(Int(v))% slow" : "on tempo")
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private func scoreChart(_ o: StudentOverview) -> some View {
        Chart {
            ForEach(o.buckets) { b in
                if let score = b.averageScore {
                    LineMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Score (%)", score * 100))
                        .foregroundStyle(PP.accent)
                    PointMark(x: .value("Day", b.start, unit: o.bucketUnit), y: .value("Score (%)", score * 100))
                        .foregroundStyle(PP.accent)
                }
            }
        }
        .chartXScale(domain: o.domain)
        .chartYScale(domain: 0...100)
        .frame(height: 150)
    }

    // MARK: Lists

    private func trends(_ o: StudentOverview) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: PP.Space.s3)], alignment: .leading,
                  spacing: PP.Space.s3) {
            ForEach(o.trends) { t in
                HStack(spacing: PP.Space.s2) {
                    Image(systemName: t.category.symbol).foregroundColor(t.category.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.category.title).font(.ppCallout)
                        Text(t.category == .tempo
                             ? "\(Int(t.earlier.rounded()))% → \(Int(t.recent.rounded()))% of takes"
                             : String(format: "%.1f → %.1f per 100 notes", t.earlier, t.recent))
                            .font(.ppCaption).foregroundColor(PP.inkMuted).monospacedDigit()
                    }
                    Spacer()
                    trendBadge(t)
                }
            }
        }
    }

    /// Better, worse or about the same, always in words as well as colour.
    @ViewBuilder
    private func trendBadge(_ t: StudentOverview.Trend) -> some View {
        let delta = t.recent - t.earlier
        if t.earlier == 0 && t.recent == 0 {
            Label("None", systemImage: "checkmark").foregroundColor(PP.success)
                .font(.ppCaption)
        } else if abs(delta) < max(0.5, t.earlier * 0.1) {
            Label("Steady", systemImage: "arrow.right").foregroundColor(PP.inkMuted).font(.ppCaption)
        } else if delta < 0 {
            Label("Better", systemImage: "arrow.down.right").foregroundColor(PP.success).font(.ppCaption)
        } else {
            Label("Worse", systemImage: "arrow.up.right").foregroundColor(PP.mistake).font(.ppCaption)
        }
    }

    private var tutorProgress: some View {
        VStack(spacing: 0) {
            ForEach(tutorLessons) { lesson in
                HStack(spacing: PP.Space.s3) {
                    Image(systemName: lesson.mastered ? "checkmark.seal.fill" : "sparkles")
                        .foregroundColor(lesson.mastered ? PP.success : PP.accent).frame(width: 20)
                    VStack(alignment: .leading, spacing: PP.Space.s1) {
                        Text(lesson.title).font(.ppCallout).lineLimit(1)
                        if let total = lesson.stepCount, total > 0 {
                            let share = CGFloat(min(lesson.stepsDone, total)) / CGFloat(total)
                            Capsule().fill(PP.inkStaff.opacity(0.3)).frame(width: 260, height: 6)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(lesson.mastered ? PP.success : PP.accent).frame(width: 260 * share, height: 6)
                                }
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(lesson.mastered ? "Passed" : lesson.stepCount.map { "\(min(lesson.stepsDone, $0)) of \($0) steps" }
                             ?? "\(lesson.stepsDone) step\(lesson.stepsDone == 1 ? "" : "s") done")
                            .font(.ppCaption)
                            .foregroundColor(lesson.mastered ? PP.success : PP.ink)
                        if let stars = lesson.stars {
                            Text("Last Perform: \(stars) of 3 stars").font(.ppCaption).foregroundColor(PP.inkMuted)
                        }
                    }
                    .monospacedDigit()
                }
                .padding(.vertical, PP.Space.s2)
                if lesson.id != tutorLessons.last?.id { Divider() }
            }
        }
    }

    private func troubleSpots(_ o: StudentOverview) -> some View {
        VStack(spacing: 0) {
            ForEach(o.troubleSpots) { spot in
                HStack(spacing: PP.Space.s3) {
                    Image(systemName: spot.category.symbol).foregroundColor(spot.category.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(pieceName(spot.piece)), bar \(spot.measure)")
                            .font(.ppCallout)
                        Text("Mostly \(spot.category.title.lowercased())").font(.ppCaption).foregroundColor(PP.inkMuted)
                    }
                    Spacer()
                    Text("\(spot.count) takes").font(.ppCaption).foregroundColor(PP.inkMuted).monospacedDigit()
                }
                .padding(.vertical, PP.Space.s2)
                if spot.id != o.troubleSpots.last?.id { Divider() }
            }
        }
    }

    private func pieces(_ o: StudentOverview) -> some View {
        Grid(alignment: .leading, horizontalSpacing: PP.Space.s4, verticalSpacing: PP.Space.s2) {
            GridRow {
                Text("Piece"); Text("Takes"); Text("Best"); Text("Last"); Text("Most common mistake")
            }
            .font(.ppCaption).foregroundColor(PP.inkMuted)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(o.pieces.prefix(12)) { p in
                GridRow {
                    HStack(spacing: PP.Space.s1) {
                        Text(pieceName(p.piece)).lineLimit(1)
                        if p.tutored {
                            Image(systemName: "sparkles").foregroundColor(PP.accent).help("Learned with the AI tutor")
                                .accessibilityLabel("with the AI tutor")
                        }
                    }
                    Text("\(p.takes)").monospacedDigit()
                    Text("\(Int((p.bestScore * 100).rounded()))%").monospacedDigit()
                    Text("\(Int((p.lastScore * 100).rounded()))%").monospacedDigit()
                    if let m = p.mainMistake {
                        Label(m.title, systemImage: m.symbol).foregroundColor(PP.ink)
                    } else {
                        Label("None", systemImage: "checkmark").foregroundColor(PP.success)
                    }
                }
                .font(.ppCallout)
            }
        }
    }
}
#endif
