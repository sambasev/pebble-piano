import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Measures pitch from the image of one system: staff lines by row projection (after
/// deskewing), noteheads by fitting a notehead-sized ellipse (hollow heads are filled in first),
/// each pitch from its head's height against the staff lines, and the bar lines.
/// A Swift port of `scripts/notehead_geometry.py`; the Beyer fixtures test both.
public enum NoteheadGeometry {

    // MARK: Results

    public struct Staff: Equatable, Sendable {
        /// The five line heights, top to bottom, in pixels.
        public var lines: [Double]
        /// Distance between lines.
        public var spacing: Double
        public var top: Double { lines[0] }
        public var bottom: Double { lines[4] }
    }

    public struct Head: Equatable, Sendable {
        public var x: Double
        public var y: Double
        /// Steps above the bottom line (0 = bottom line, −2 = first ledger line below).
        public var position: Int
        /// How far the head sits from that line or space, in steps (−0.5…0.5). Above 0.3 it is
        /// between a line and a space, and the pitch isn't trusted.
        public var offset: Double
        public var filled: Bool
        public var pitch: String

        public var isClear: Bool { abs(offset) <= 0.3 }
    }

    public struct System: Sendable {
        public var upper: Staff
        public var lower: Staff
        public var upperHeads: [Head]
        public var lowerHeads: [Head]
        /// Bar edges, left to right: where the music starts, each bar line, and the end of the
        /// staff when the system doesn't end on a bar line. Bar i lies between edges i and i+1.
        public var barEdges: [Double]
        /// The clefs found at the start of each staff (the caller's guess where none was found).
        public var upperClef: SystemReading.Clef = .treble
        public var lowerClef: SystemReading.Clef = .treble

        public func heads(_ staff: SystemReading.StaffName) -> [Head] { staff == .upper ? upperHeads : lowerHeads }
        public var barCount: Int { max(0, barEdges.count - 1) }
    }

    public enum GeometryError: Error, Equatable {
        case unreadableImage
        case staffNotFound(Int)
    }

    // MARK: Entry point

    #if canImport(CoreGraphics)
    public static func measure(png: Data, clefs: (SystemReading.Clef, SystemReading.Clef) = (.treble, .treble)) throws -> System {
        guard let gray = Gray.decode(png) else { throw GeometryError.unreadableImage }
        return try measure(gray, clefs: clefs)
    }
    #endif

    public static func measure(_ gray: Gray, clefs: (SystemReading.Clef, SystemReading.Clef) = (.treble, .treble)) throws -> System {
        let ink = deskew(gray.binarized())
        var staves = staffLines(ink)
        guard staves.count >= 2 else { throw GeometryError.staffNotFound(staves.count) }
        if staves.count > 2 {
            // The pair of neighbouring staves whose gap looks most like a grand staff's.
            let pairs = (0..<(staves.count - 1)).map { (staves[$0], staves[$0 + 1]) }
            let best = pairs.min { abs(($0.1.top - $0.0.bottom) - 2.5 * $0.0.spacing) < abs(($1.1.top - $1.0.bottom) - 2.5 * $1.0.spacing) }!
            staves = [best.0, best.1]
        }
        let upper = staves[0], lower = staves[1]
        let split = (upper.bottom + lower.top) / 2
        let header = headerEnds(ink, upper, lower)
        let (startUpper, startLower) = (header.upper, header.lower)
        let clefs = (header.upperClef ?? clefs.0, header.lowerClef ?? clefs.1)

        var upperHeads: [Head] = [], lowerHeads: [Head] = []
        for h in noteheads(ink, spacing: (upper.spacing + lower.spacing) / 2).sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) {
            let isUpper = h.y < split
            let staff = isUpper ? upper : lower
            if h.x < Double(isUpper ? startUpper : startLower) { continue }
            let exact = (staff.bottom - h.y) / (staff.spacing / 2)
            let pos = Int(exact.rounded(.toNearestOrEven))
            guard (-5...13).contains(pos),
                  hasLedgers(ink, x: h.x, width: h.width, bottom: staff.bottom, spacing: staff.spacing, position: pos)
            else { continue }  // text, fingering, clef parts: off the staff with no ledger lines
            let clef = isUpper ? clefs.0 : clefs.1
            let head = Head(x: h.x, y: h.y, position: pos, offset: exact - Double(pos), filled: h.filled,
                            pitch: StaffPitch.name(clef: clef, position: pos))
            if isUpper { upperHeads.append(head) } else { lowerHeads.append(head) }
        }

        let edges = barEdges(ink, upper, lower, start: Double(min(startUpper, startLower)))
        // Drop "heads" sitting on a bar line (thick final bar lines can look like heads).
        let notOnBar: (Head) -> Bool = { h in edges.allSatisfy { abs(h.x - $0) > 0.7 * upper.spacing } }
        return System(upper: upper, lower: lower, upperHeads: upperHeads.filter(notOnBar),
                      lowerHeads: lowerHeads.filter(notOnBar), barEdges: edges,
                      upperClef: clefs.0, lowerClef: clefs.1)
    }

    // MARK: Deskew

    /// Shears the image so staff lines are horizontal: the slope whose row projection is sharpest.
    static func deskew(_ ink: Bitmap, maxDegrees: Double = 1.5, step: Double = 0.05) -> Bitmap {
        let w = ink.width, h = ink.height
        var points: [(Int, Int)] = []
        points.reserveCapacity(w * h / 8)
        for y in 0..<h { for x in 0..<w where ink[x, y] { points.append((x, y)) } }
        let cx = Double(w) / 2
        let pad = Int(ceil(Double(w) * tan(maxDegrees * .pi / 180))) + 2
        var bestScore = -1.0, bestSlope = 0.0
        var counts = [Int](repeating: 0, count: h + 2 * pad)
        let steps = Int((2 * maxDegrees / step).rounded())
        for i in 0...steps {
            let slope = tan((-maxDegrees + Double(i) * step) * .pi / 180)
            for k in counts.indices { counts[k] = 0 }
            for (x, y) in points {
                let b = Int((Double(y) - (Double(x) - cx) * slope).rounded()) + pad
                if b >= 0 && b < counts.count { counts[b] += 1 }
            }
            var score = 0.0
            for c in counts where c > 0 { score += Double(c) * Double(c) }
            if score > bestScore { bestScore = score; bestSlope = slope }
        }
        if abs(bestSlope) < 1e-9 { return ink }
        var out = Bitmap(width: w, height: h)
        for x in 0..<w {
            let shift = Int(((Double(x) - cx) * bestSlope).rounded())
            for y in 0..<h {
                let sy = y + shift
                if sy >= 0 && sy < h && ink[x, sy] { out[x, y] = true }
            }
        }
        return out
    }

    // MARK: Staff lines

    /// Groups of five evenly spaced, strongly inked rows, top to bottom.
    static func staffLines(_ ink: Bitmap) -> [Staff] {
        let rows = (0..<ink.height).map { ink.rowCount($0) }
        let threshold = 0.45 * Double(rows.max() ?? 0)
        var runs: [(Int, Int)] = []
        var start: Int?
        for y in 0...ink.height {
            let on = y < ink.height && Double(rows[y]) > threshold
            if on, start == nil { start = y }
            if !on, let s = start { runs.append((s, y)); start = nil }
        }
        // A beam lying on a line widens its run: centre such a run on the line's own rows.
        let lengths = runs.map { $0.1 - $0.0 }.sorted()
        let typical = lengths.isEmpty ? 0 : (lengths.count % 2 == 1 ? Double(lengths[lengths.count / 2])
            : Double(lengths[lengths.count / 2 - 1] + lengths[lengths.count / 2]) / 2)
        let lines: [Double] = runs.map { run in
            var (a, b) = run
            if Double(b - a) > 2 * typical + 1 {
                let peak = Double(rows[a..<b].max()!)
                let core = (a..<b).filter { Double(rows[$0]) >= 0.85 * peak }
                (a, b) = (core.first!, core.last! + 1)
            }
            return Double(a + b - 1) / 2
        }
        var staves: [Staff] = []
        var i = 0
        while i + 4 < lines.count {
            let five = Array(lines[i..<(i + 5)])
            let gaps = zip(five.dropFirst(), five).map { $0 - $1 }
            let mean = gaps.reduce(0, +) / 4
            if gaps.max()! - gaps.min()! <= 0.25 * mean {
                staves.append(Staff(lines: five, spacing: mean))
                i += 5
            } else {
                i += 1
            }
        }
        return staves
    }

    // MARK: Header (clef, time signature)

    /// Removes thin horizontal lines (staff and ledger lines) where nothing crosses them.
    static func withoutLines(_ ink: Bitmap, spacing sp: Double) -> Bitmap {
        let t = max(1, Int((0.18 * sp).rounded())) + 1
        var out = ink
        for y in 0..<ink.height where Double(ink.rowCount(y)) > 0.3 * Double(ink.width) {
            for x in 0..<ink.width where ink[x, y] {
                let up = y - t >= 0 && ink[x, y - t]
                let down = y + t < ink.height && ink[x, y + t]
                if !up && !down { out[x, y] = false }
            }
        }
        return out
    }

    struct Glyph { var x0, x1, y0, y1: Int
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
        var centerY: Double { Double(y0 + y1) / 2 }
    }

    /// (where the clef ends, time-signature candidates) for one staff.
    static func headerGlyphs(_ ink: Bitmap, _ staff: Staff, lineless: Bitmap) -> (Int, [Glyph], SystemReading.Clef?) {
        let sp = staff.spacing
        let y0 = max(0, Int(staff.top - 3 * sp))
        let y1 = min(ink.height, Int(staff.bottom + 3 * sp))
        let glyphs = components(lineless, rows: y0..<y1)
        let w = Double(ink.width)
        // A treble clef reaches well above and below the staff; a bass clef is ~3 spaces tall and
        // hangs from the top line.
        func kind(_ g: Glyph) -> SystemReading.Clef? {
            guard (1.5 * sp...6 * sp).contains(Double(g.width)), Double(g.x0) < 0.3 * w else { return nil }
            if Double(g.height) >= 4.5 * sp { return .treble }
            if (2.4 * sp...4.2 * sp).contains(Double(g.height)), abs(Double(g.y0) - staff.top) <= 0.8 * sp,
               Double(g.y1) <= staff.bottom + 0.6 * sp { return .bass }
            return nil
        }
        // The leftmost: slurs joined to notes can look tall and wide too.
        guard let clef = glyphs.filter({ kind($0) != nil }).min(by: { ($0.x0, $0.x1) < ($1.x0, $1.x1) })
        else { return (0, [], nil) }
        let end = clef.x1
        let mid = (staff.top + staff.bottom) / 2
        let sig = glyphs.filter {
            Double($0.x0) >= Double(end) - 0.2 * sp && Double($0.x0) <= Double(end) + 3 * sp
                && (1.4 * sp...4.2 * sp).contains(Double($0.height))  // the two digits can join up
                && (0.6 * sp...2.4 * sp).contains(Double($0.width))
                && abs($0.centerY - mid) <= 1.2 * sp
        }
        return (end, sig, kind(clef))
    }

    /// Where the music starts on each staff: after the clef, and after the time signature when
    /// there is one. A time signature is on both staves at the same place, so a lone "glyph"
    /// there is a note (continuation systems have no time signature). Key signatures aren't
    /// handled yet: the demo pieces are in C major.
    static func headerEnds(_ ink: Bitmap, _ upper: Staff, _ lower: Staff)
        -> (upper: Int, lower: Int, upperClef: SystemReading.Clef?, lowerClef: SystemReading.Clef?) {
        let lineless = withoutLines(ink, spacing: upper.spacing)
        let (eu, su, cu) = headerGlyphs(ink, upper, lineless: lineless)
        let (el, sl, cl) = headerGlyphs(ink, lower, lineless: lineless)
        var sigEnd = 0
        for a in su {
            for b in sl where Double(min(a.x1, b.x1) - max(a.x0, b.x0)) >= 0.5 * Double(min(a.width, b.width)) {
                sigEnd = max(sigEnd, a.x1, b.x1)
            }
        }
        return (max(eu, sigEnd), max(el, sigEnd), cu, cl)
    }

    /// Connected components (4-connected) within the given rows, as bounding boxes in image
    /// coordinates.
    static func components(_ img: Bitmap, rows: Range<Int>) -> [Glyph] {
        let w = img.width
        let h = rows.count
        guard h > 0 else { return [] }
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Glyph] = []
        var stack: [Int] = []
        for y in 0..<h {
            for x in 0..<w where img[x, y + rows.lowerBound] && !seen[y * w + x] {
                var g = Glyph(x0: x, x1: x + 1, y0: y, y1: y + 1)
                seen[y * w + x] = true
                stack.append(y * w + x)
                while let p = stack.popLast() {
                    let px = p % w, py = p / w
                    g.x0 = min(g.x0, px); g.x1 = max(g.x1, px + 1)
                    g.y0 = min(g.y0, py); g.y1 = max(g.y1, py + 1)
                    for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
                    where nx >= 0 && nx < w && ny >= 0 && ny < h {
                        let q = ny * w + nx
                        if !seen[q] && img[nx, ny + rows.lowerBound] { seen[q] = true; stack.append(q) }
                    }
                }
                g.y0 += rows.lowerBound; g.y1 += rows.lowerBound
                out.append(g)
            }
        }
        return out
    }

    // MARK: Noteheads

    struct RawHead { var x: Double; var y: Double; var width: Double; var filled: Bool }

    /// Hollow-notehead holes: small, squat, ellipse-like holes. Boxes between staff lines, stems
    /// and bar lines are bigger, taller or rectangular. (LilyPond's half notes have a long
    /// diagonal slit, almost as wide as the head, so no test of walls beside the hole.)
    static func hollowFill(_ ink: Bitmap, spacing sp: Double) -> Bitmap {
        let w = ink.width, h = ink.height
        // Background reachable from the border (4-connected); the rest of the background is holes.
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func push(_ x: Int, _ y: Int) {
            let i = y * w + x
            if !ink[x, y] && !outside[i] { outside[i] = true; stack.append(i) }
        }
        for x in 0..<w { push(x, 0); push(x, h - 1) }
        for y in 0..<h { push(0, y); push(w - 1, y) }
        while let p = stack.popLast() {
            let px = p % w, py = p / w
            if px > 0 { push(px - 1, py) }
            if px < w - 1 { push(px + 1, py) }
            if py > 0 { push(px, py - 1) }
            if py < h - 1 { push(px, py + 1) }
        }
        var holes = Bitmap(width: w, height: h)
        for y in 0..<h { for x in 0..<w where !ink[x, y] && !outside[y * w + x] { holes[x, y] = true } }

        var fill = Bitmap(width: w, height: h)
        for g in components(holes, rows: 0..<h) {
            var area = 0
            for y in g.y0..<g.y1 { for x in g.x0..<g.x1 where holes[x, y] { area += 1 } }
            let a = Double(area), hw = Double(g.width), hh = Double(g.height)
            guard a >= 0.04 * sp * sp, a <= 0.6 * sp * sp, hw >= 0.25 * sp, hw <= 1.4 * sp, hh <= 0.95 * sp,
                  a / (hw * hh) <= 0.85 else { continue }
            // Mark this hole's pixels (only those connected to this component's box).
            for y in g.y0..<g.y1 { for x in g.x0..<g.x1 where holes[x, y] { fill[x, y] = true } }
        }
        return fill
    }

    /// A tilted ellipse mask (noteheads tilt up to the right by ~20°), as offsets from its centre,
    /// within a square of half-size r (pixels outside the square are clipped, as in the probe).
    struct Mask { var r: Int; var cells: [Bool]
        var side: Int { 2 * r + 1 }
        subscript(dx: Int, dy: Int) -> Bool {
            get { abs(dx) <= r && abs(dy) <= r && cells[(dy + r) * side + dx + r] }
        }
        var offsets: [(Int, Int)] {
            var out: [(Int, Int)] = []
            for dy in -r...r { for dx in -r...r where self[dx, dy] { out.append((dx, dy)) } }
            return out
        }
    }

    static func ellipse(_ sp: Double, sx: Double, sy: Double, r: Int? = nil) -> Mask {
        let a = 0.62 * sp * sx, b = 0.46 * sp * sy
        let r = r ?? Int(ceil(max(a, b))) + 1
        let t = 20.0 * .pi / 180
        var cells = [Bool](repeating: false, count: (2 * r + 1) * (2 * r + 1))
        for dy in -r...r {
            for dx in -r...r {
                let u = Double(dx) * cos(t) + Double(dy) * sin(t)
                let v = -Double(dx) * sin(t) + Double(dy) * cos(t)
                cells[(dy + r) * (2 * r + 1) + dx + r] = (u / a) * (u / a) + (v / b) * (v / b) <= 1
            }
        }
        return Mask(r: r, cells: cells)
    }

    /// Binary dilation with a cross, clipped to the mask's square.
    static func dilate(_ m: Mask, iterations: Int) -> Mask {
        var cur = m
        for _ in 0..<iterations {
            var next = cur
            for dy in -cur.r...cur.r {
                for dx in -cur.r...cur.r where !cur[dx, dy] {
                    if cur[dx - 1, dy] || cur[dx + 1, dy] || cur[dx, dy - 1] || cur[dx, dy + 1] {
                        next.cells[(dy + cur.r) * cur.side + dx + cur.r] = true
                    }
                }
            }
            cur = next
        }
        return cur
    }

    static func noteheads(_ ink: Bitmap, spacing sp: Double) -> [RawHead] {
        let w = ink.width, h = ink.height
        let hollow = hollowFill(ink, spacing: sp)
        var solid = ink
        for i in solid.bits.indices where hollow.bits[i] { solid.bits[i] = true }
        let integral = solid.integral()

        var score = [Double](repeating: 0, count: w * h)
        for sx in [1.0, 1.3] {  // black and half noteheads, and the wider whole notes
            let fillMask = ellipse(sp, sx: 0.9 * sx, sy: 0.9)
            let base = ellipse(sp, sx: sx, sy: 1.0)
            let inner = dilate(base, iterations: 1)
            let big = dilate(inner, iterations: max(2, Int(0.3 * sp)))
            var ringCells = big.cells
            for i in ringCells.indices where inner.cells[i] { ringCells[i] = false }
            let ring = Mask(r: big.r, cells: ringCells)
            let fillOffsets = fillMask.offsets, ringOffsets = ring.offsets
            let fillCount = Double(fillOffsets.count), ringCount = Double(ringOffsets.count)
            // In a chord of stacked thirds the heads touch above and below: then judge by the
            // ring's sides alone.
            let half = Int(0.45 * sp * sx)
            let sideOffsets = ringOffsets.filter { abs($0.0) > half }
            let sideCount = Double(max(1, sideOffsets.count))
            // Quick reject: a box inside the ellipse must be nearly all ink.
            let qa = max(1, Int(0.3 * sp * sx)), qb = max(1, Int(0.2 * sp))
            for y in 0..<h {
                for x in 0..<w where solid[x, y] {
                    if integral.fraction(x0: x - qa, y0: y - qb, x1: x + qa + 1, y1: y + qb + 1) < 0.8 { continue }
                    var inside = 0
                    for (dx, dy) in fillOffsets where solid.get(x + dx, y + dy) { inside += 1 }
                    let fill = Double(inside) / fillCount
                    guard fill >= 0.88 else { continue }
                    var around = 0
                    for (dx, dy) in ringOffsets where solid.get(x + dx, y + dy) { around += 1 }
                    let ar = Double(around) / ringCount
                    if ar > 0.55 {
                        guard fill >= 0.92 else { continue }
                        var beside = 0
                        for (dx, dy) in sideOffsets where solid.get(x + dx, y + dy) { beside += 1 }
                        guard Double(beside) / sideCount <= 0.35 else { continue }
                    }
                    let s = fill - 0.5 * min(ar, 0.55)
                    if s > score[y * w + x] { score[y * w + x] = s }
                }
            }
        }

        // Not a notehead if ink continues straight above and below it (thick bar lines, clef stems).
        let d = Int((1.1 * sp).rounded()), c = max(1, Int(0.12 * sp))
        for y in 0..<h {
            for x in 0..<w where score[y * w + x] > 0 {
                var above = true, below = true
                for k in -c...c {
                    let xx = min(max(x + k, 0), w - 1)
                    if !solid.get(xx, y - d) { above = false }
                    if !solid.get(xx, y + d) { below = false }
                }
                if above && below { score[y * w + x] = 0 }
            }
        }

        // Local maxima over a notehead-sized window, then greedy suppression of close ones.
        let wy = max(1, Int(0.8 * sp)), wx = max(1, Int(1.1 * sp))
        var peaks: [(Double, Int, Int)] = []
        for y in 0..<h {
            for x in 0..<w where score[y * w + x] > 0 {
                let s = score[y * w + x]
                var isMax = true
                search: for yy in max(0, y - wy / 2)..<min(h, y - wy / 2 + wy) {
                    for xx in max(0, x - wx / 2)..<min(w, x - wx / 2 + wx) where score[yy * w + xx] > s {
                        isMax = false
                        break search
                    }
                }
                if isMax { peaks.append((s, x, y)) }
            }
        }
        peaks.sort { $0.0 > $1.0 }
        var taken: [(Int, Int)] = []
        var out: [RawHead] = []
        for (_, x, y) in peaks {
            if taken.contains(where: { Double(abs(x - $0.0)) < 0.9 * sp && Double(abs(y - $0.1)) < 0.7 * sp }) { continue }
            taken.append((x, y))
            var filled = true
            for yy in (y - 2)...(y + 2) { for xx in (x - 2)...(x + 2) where hollow.get(xx, yy) { filled = false } }
            out.append(RawHead(x: Double(x), y: Double(y), width: 1.25 * sp, filled: filled))
        }
        return splitChords(solid, out, spacing: sp)
    }

    /// Stacked chord heads (thirds) touch and read as one tall blob, where the ellipse fit puts
    /// heads at the wrong heights or misses one: count the heads from the blob's height instead.
    static func splitChords(_ solid: Bitmap, _ heads: [RawHead], spacing sp: Double) -> [RawHead] {
        let w = solid.width, h = solid.height
        let half = Int((0.6 * sp).rounded())
        let thin = max(1, Int((0.25 * sp).rounded()))
        func wide(_ y: Int, _ x: Int) -> Bool {
            var n = 0
            for xx in max(0, x - half)..<min(w, x + half + 1) where solid[xx, y] { n += 1 }
            return Double(n) >= 0.75 * sp
        }
        // Ink right across, beyond a head on both sides: a staff line, or a beam if it's thick.
        func spans(_ y: Int, _ x: Int) -> Bool { solid[max(0, x - 2 * half), y] && solid[min(w - 1, x + 2 * half), y] }
        func grow(_ y0: Int, _ x: Int, _ d: Int) -> Int {
            var y = y0, run = 0
            while y + d >= 0 && y + d < h && wide(y + d, x) {
                y += d
                run = spans(y, x) ? run + 1 : 0
                if run > thin { return y - d * run }
            }
            return y - d * run
        }
        let near = 0.9 * sp
        var out: [RawHead] = []
        var done: [(x: Double, top: Int, bottom: Int)] = []
        for head in heads.sorted(by: { $0.y < $1.y }) {
            let x = Int(head.x.rounded()), y = Int(head.y.rounded())
            if done.contains(where: { abs(head.x - $0.x) < near && ($0.top...$0.bottom).contains(y) }) { continue }
            let top = grow(y, x, -1), bottom = grow(y, x, 1)
            let n = Int((Double(bottom - top + 1) / sp).rounded())
            let inBlob: (RawHead) -> Bool = { abs($0.x - head.x) < near && Double(top - 2)...Double(bottom + 2) ~= $0.y }
            let group = heads.filter(inBlob).sorted { $0.y < $1.y }
            let step = Double(bottom - top + 1) / Double(max(n, 1))
            let evenlySpaced = group.count == n && group.enumerated().allSatisfy {
                abs($0.element.y - (Double(top) + step * (Double($0.offset) + 0.5))) < 0.25 * sp
            }
            if n <= 1 {
                out.append(head)
                done.append((head.x, y, y))
            } else if evenlySpaced {
                out.removeAll(where: inBlob)
                out.append(contentsOf: group)
                done.append((head.x, top, bottom))
            } else {
                out.removeAll(where: inBlob)
                for i in 0..<n {
                    out.append(RawHead(x: head.x, y: Double(top) + step * (Double(i) + 0.5), width: head.width, filled: head.filled))
                }
                done.append((head.x, top, bottom))
            }
        }
        return out.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// A note off the staff (C4 and below, A5 and above in treble) sits on or between ledger lines.
    static func hasLedgers(_ ink: Bitmap, x: Double, width w: Double, bottom: Double, spacing sp: Double, position pos: Int) -> Bool {
        if (-1...9).contains(pos) { return true }
        let ks = pos < -1 ? Array(stride(from: -2, through: pos, by: -2)) : Array(stride(from: 10, through: pos, by: 2))
        let reach = max(2, Int(0.3 * sp)), band = max(1, Int(0.12 * sp))
        for k in ks {
            let y = Int((bottom - Double(k) * sp / 2).rounded())
            let rows = max(0, y - band)..<min(ink.height, y + band + 1)
            let l0 = Int(x - w / 2) - reach, l1 = Int(x - w / 2)
            let r0 = Int(x + w / 2), r1 = Int(x + w / 2) + reach
            var best = 0.0
            for row in rows {
                if l1 > 0 { best = max(best, ink.mean(rows: row..<(row + 1), cols: max(0, l0)..<l1)) }
                if r1 <= ink.width { best = max(best, ink.mean(rows: row..<(row + 1), cols: r0..<r1)) }
            }
            if best < 0.6 { return false }
        }
        return true
    }

    // MARK: Bar lines

    /// x of each bar line running from the upper staff's top line to the lower staff's bottom line.
    static func barLines(_ ink: Bitmap, _ upper: Staff, _ lower: Staff) -> [Double] {
        let top = Int(upper.top), bottom = Int(lower.bottom)
        guard bottom > top else { return [] }
        let span = Double(bottom - top + 1)
        var groups: [[Int]] = []
        for x in 0..<ink.width {
            var n = 0
            for y in top...bottom where ink[x, y] { n += 1 }
            guard Double(n) / span >= 0.9 else { continue }
            if let last = groups.last?.last, x - last <= 2 { groups[groups.count - 1].append(x) } else { groups.append([x]) }
        }
        var xs: [Double] = []
        for g in groups {  // a thin+thick final bar line counts once
            let x = Double(g.first! + g.last!) / 2
            if let last = xs.last, x - last < 1.2 * upper.spacing { xs[xs.count - 1] = x } else { xs.append(x) }
        }
        return xs
    }

    static func barEdges(_ ink: Bitmap, _ upper: Staff, _ lower: Staff, start: Double) -> [Double] {
        let sp = upper.spacing
        let rows = upper.lines.map { Int($0.rounded()) }
        var right = 0
        for x in 0..<ink.width where rows.filter({ ink[x, $0] }).count >= 4 { right = x }
        var edges = [start] + barLines(ink, upper, lower).filter { $0 > start + sp }
        if edges.last! < Double(right) - 1.5 * sp { edges.append(Double(right)) }
        return foldNarrowBars(edges, spacing: sp)
    }

    /// A "bar" too narrow to hold a note is a repeat sign or a double bar line, not a bar:
    /// fold it into its neighbour (the next bar, or the previous one at the end).
    static func foldNarrowBars(_ edges: [Double], spacing sp: Double) -> [Double] {
        var e = edges
        var k = 0
        while k + 1 < e.count && e.count > 2 {
            if e[k + 1] - e[k] < 2.5 * sp {
                e.remove(at: k + 1 == e.count - 1 ? k : k + 1)
            } else {
                k += 1
            }
        }
        return e
    }
}

// MARK: - Images

/// An 8-bit grayscale image.
public struct Gray: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    #if canImport(CoreGraphics)
    public static func decode(_ data: Data) -> Gray? {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }
        return from(image)
    }

    public static func from(_ image: CGImage) -> Gray? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 255, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Gray(width: w, height: h, pixels: pixels) : nil
    }
    #endif

    /// Ink where darker than Otsu's threshold.
    public func binarized() -> Bitmap {
        var hist = [Double](repeating: 0, count: 256)
        for p in pixels { hist[Int(p)] += 1 }
        let total = Double(pixels.count)
        var w = 0.0, mu = 0.0, muTotal = 0.0
        for i in 0..<256 { muTotal += Double(i) * hist[i] / total }
        var best = -1.0, threshold = 128
        for i in 0..<256 {
            w += hist[i] / total
            mu += Double(i) * hist[i] / total
            let between = (muTotal * w - mu) * (muTotal * w - mu) / (w * (1 - w) + 1e-12)
            if between > best { best = between; threshold = i }
        }
        var out = Bitmap(width: width, height: height)
        for i in pixels.indices where Int(pixels[i]) < threshold { out.bits[i] = true }
        return out
    }
}

/// A black-and-white image: true = ink.
public struct Bitmap: Sendable {
    public var width: Int
    public var height: Int
    public var bits: [Bool]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bits = [Bool](repeating: false, count: width * height)
    }

    public subscript(x: Int, y: Int) -> Bool {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    /// False outside the image.
    func get(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height && bits[y * width + x]
    }

    func rowCount(_ y: Int) -> Int {
        var n = 0
        for x in 0..<width where bits[y * width + x] { n += 1 }
        return n
    }

    func mean(rows: Range<Int>, cols: Range<Int>) -> Double {
        let r = rows.clamped(to: 0..<height), c = cols.clamped(to: 0..<width)
        guard !r.isEmpty, !c.isEmpty else { return 0 }
        var n = 0
        for y in r { for x in c where bits[y * width + x] { n += 1 } }
        return Double(n) / Double(r.count * c.count)
    }

    func integral() -> Integral { Integral(self) }
}

/// Summed-area table for O(1) ink counts over boxes.
struct Integral {
    let width: Int, height: Int
    var sums: [Int32]

    init(_ b: Bitmap) {
        width = b.width; height = b.height
        sums = [Int32](repeating: 0, count: (b.width + 1) * (b.height + 1))
        for y in 0..<b.height {
            var row: Int32 = 0
            for x in 0..<b.width {
                if b.bits[y * b.width + x] { row += 1 }
                sums[(y + 1) * (width + 1) + x + 1] = sums[y * (width + 1) + x + 1] + row
            }
        }
    }

    /// Fraction of ink in [x0, x1) × [y0, y1), clamped to the image; 0 for an empty box.
    func fraction(x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
        let a = max(0, x0), b = max(0, y0), c = min(width, x1), d = min(height, y1)
        guard c > a, d > b else { return 0 }
        let s = sums[d * (width + 1) + c] - sums[b * (width + 1) + c] - sums[d * (width + 1) + a] + sums[b * (width + 1) + a]
        return Double(s) / Double((c - a) * (d - b))
    }
}
