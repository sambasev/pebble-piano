"""Measures pitch from the image (hackathon probe 3).

Staff lines by row projection (after deskewing), noteheads by fitting a notehead-sized ellipse
(hollow heads are filled in first), pitch from each head's height against the staff lines.
Needs numpy, scipy and Pillow:  python3 -m pip install numpy scipy pillow
"""
WALL, RATIO = 0.45, 0.85
HOLE_W, WALLS = 1.4, False  # hollow-notehead hole: min ink on each side wall, max fill of its box
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

LETTERS = "CDEFGAB"
BOTTOM_LINE = {"treble": 4 * 7 + 2, "bass": 2 * 7 + 4}  # E4, G2 as diatonic indices


def pitch_name(clef, position):
    i = BOTTOM_LINE[clef] + position
    return f"{LETTERS[i % 7]}{i // 7}"


def deskew(ink, max_deg=1.5, step=0.05):
    """Rotates so staff lines are horizontal: the angle whose row projection is sharpest."""
    best, best_a = -1, 0.0
    small = ink[:, ::2]
    for a in np.arange(-max_deg, max_deg + 1e-9, step):
        r = ndi.rotate(small.astype(np.uint8), a, reshape=False, order=0)
        score = (r.sum(1).astype(np.float64) ** 2).sum()
        if score > best:
            best, best_a = score, a
    if abs(best_a) < 1e-6:
        return ink, 0.0
    # The search ran on a 2x horizontally squashed image: convert the angle back.
    a = float(np.degrees(np.arctan(np.tan(np.radians(best_a)) / 2)))
    return ndi.rotate(ink.astype(np.uint8), a, reshape=False, order=0).astype(bool), a


def load(path, threshold=None):
    g = np.asarray(Image.open(path).convert("L"), dtype=np.float32)
    if threshold is None:  # Otsu
        hist, edges = np.histogram(g, 256, (0, 256))
        p = hist / hist.sum(); w = np.cumsum(p); mu = np.cumsum(p * np.arange(256))
        sb = (mu[-1] * w - mu) ** 2 / (w * (1 - w) + 1e-12)
        threshold = int(np.nanargmax(sb))
    ink, _ = deskew(g < threshold)
    return ink


def staff_lines(ink):
    """Groups of 5 evenly spaced horizontal lines → [(ys of 5 lines, spacing)] top to bottom."""
    h, w = ink.shape
    rows = ink.sum(1)
    strong = rows > 0.45 * rows.max()
    runs, start = [], None
    for y in range(h + 1):
        on = y < h and strong[y]
        if on and start is None:
            start = y
        elif not on and start is not None:
            runs.append((start, y)); start = None
    # A beam lying on a line widens its run: centre such a run on the line's own rows.
    typical = np.median([b - a for a, b in runs]) if runs else 0
    lines = []
    for a, b in runs:
        if b - a > 2 * typical + 1:
            core = np.nonzero(rows[a:b] >= 0.85 * rows[a:b].max())[0]
            a, b = a + core[0], a + core[-1] + 1
        lines.append((a + b - 1) / 2)
    staves, i = [], 0
    while i + 4 < len(lines):
        five = lines[i:i + 5]
        gaps = np.diff(five)
        if gaps.max() - gaps.min() <= 0.25 * gaps.mean():
            staves.append((five, float(gaps.mean()))); i += 5
        else:
            i += 1
    return staves


def has_ledgers(ink, x, w, bottom, sp, pos):
    """A note off the staff (C4 and below, A5 and above) sits on or between ledger lines."""
    if -1 <= pos <= 9:
        return True
    ks = range(-2, pos - 1, -2) if pos < -1 else range(10, pos + 1, 2)
    reach, band = max(2, int(0.3 * sp)), max(1, int(0.12 * sp))
    for k in ks:
        y = int(round(bottom - k * sp / 2))
        rows = ink[max(0, y - band):y + band + 1]
        l0, l1 = int(x - w / 2 - reach), int(x - w / 2)
        r0, r1 = int(x + w / 2), int(x + w / 2 + reach)
        left = rows[:, max(0, l0):max(0, l1)].mean(1).max() if l1 > 0 else 0
        right = rows[:, r0:r1].mean(1).max() if r1 <= ink.shape[1] else 0
        if max(left, right) < 0.6:
            return False
    return True


# ── Noteheads: fit a notehead-sized ellipse ───────────────────────────────────
from scipy.signal import fftconvolve


def ellipse_kernel_xy(sp, sx, sy):
    a, b = 0.62 * sp * sx, 0.46 * sp * sy
    R = int(np.ceil(max(a, b))) + 1
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(float)
    t = np.radians(20)
    u, v = xx * np.cos(t) + yy * np.sin(t), -xx * np.sin(t) + yy * np.cos(t)
    return (u / a) ** 2 + (v / b) ** 2 <= 1.0


def ellipse_kernel(sp, scale=1.0):
    a, b = 0.62 * sp * scale, 0.46 * sp * scale  # half width, half height of a notehead
    R = int(np.ceil(a)) + 1
    yy, xx = np.mgrid[-R:R + 1, -R:R + 1].astype(float)
    # Noteheads tilt up to the right by ~20°.
    t = np.radians(20)
    u, v = xx * np.cos(t) + yy * np.sin(t), -xx * np.sin(t) + yy * np.cos(t)
    return (u / a) ** 2 + (v / b) ** 2 <= 1.0


def without_lines(ink, sp):
    """Removes thin horizontal lines (staff and ledger lines) where nothing crosses them."""
    t = max(1, int(round(0.18 * sp)))
    up = np.zeros_like(ink); up[t + 1:] = ink[:-(t + 1)]
    down = np.zeros_like(ink); down[:-(t + 1)] = ink[t + 1:]
    # A pixel is part of a thin line if the pixels t+1 above and below are both white.
    rows = ink.mean(1) > 0.3
    thin = ink & ~up & ~down & rows[:, None]
    return ink & ~thin


def header_glyphs(ink, top, bottom, sp):
    """(clef end x, candidate time-signature glyphs) for one staff."""
    y0 = max(0, int(top - 3 * sp))
    band = without_lines(ink, sp)[y0:int(bottom + 3 * sp)]
    lab, n = ndi.label(band)
    if n == 0:
        return 0
    objs = [(sl[1].start, sl[1].stop, sl[0].stop - sl[0].start) for sl in ndi.find_objects(lab)]
    objs_full = [(sl[1].start, sl[1].stop, sl[0].stop - sl[0].start, (sl[0].start + sl[0].stop) / 2)
                 for sl in ndi.find_objects(lab)]
    W = ink.shape[1]
    tops = [sl[0].start + y0 for sl in ndi.find_objects(lab)]
    # A treble clef reaches well above and below the staff; a bass clef is ~3 spaces tall and
    # hangs from the top line.
    clefs = [o for o, t in zip(objs, tops) if 1.5 * sp <= (o[1] - o[0]) <= 6 * sp and o[0] < 0.3 * W and
             (o[2] >= 4.5 * sp or (2.4 * sp <= o[2] <= 4.2 * sp and abs(t - top) <= 0.8 * sp
                                   and t + o[2] <= bottom + 0.6 * sp))]
    if not clefs:
        return 0, []
    end = min(clefs)[1]  # the leftmost: slurs joined to notes can look tall and wide too
    # Time-signature candidates: glyphs ~2 spaces tall, centred on the staff, just after the clef.
    # (Key signatures aren't handled yet: the demo pieces are in C major.)
    mid = (top + bottom) / 2 - y0
    sig = [o for o in objs_full if end - 0.2 * sp <= o[0] <= end + 3 * sp and 1.4 * sp <= o[2] <= 4.2 * sp
           and 0.6 * sp <= o[1] - o[0] <= 2.4 * sp and abs(o[3] - mid) <= 1.5 * sp
           # Digits stay within the staff; a note's stem runs out of it.
           and o[3] - o[2] / 2 >= top - y0 - 0.4 * sp and o[3] + o[2] / 2 <= bottom - y0 + 0.4 * sp]
    # The digits fill the staff from its top line to its bottom line; a C (common or cut time)
    # sits in its middle.
    common = any(abs(o[3] - mid) <= 0.5 * sp and o[2] <= 2.6 * sp for o in sig)
    if sig and not common and (min(o[3] - o[2] / 2 for o in sig) > top - y0 + 0.7 * sp
                or max(o[3] + o[2] / 2 for o in sig) < bottom - y0 - 0.7 * sp):
        sig = []
    return end, sig


def header_ends(ink, upper, lower):
    """Where the music starts on each staff: after the clef, and after the time signature when
    there is one. A time signature appears on both staves at the same place, so a lone
    "glyph" there is a note (continuation systems have no time signature)."""
    sp = upper[1]
    (eu, su), (el, sl_) = (header_glyphs(ink, upper[0][0], upper[0][4], sp),
                           header_glyphs(ink, lower[0][0], lower[0][4], sp))
    pairs = [(a, b) for a in su for b in sl_ if min(a[1], b[1]) - max(a[0], b[0]) >= 0.5 * min(a[1] - a[0], b[1] - b[0])]
    sig_end = max([a[1] for a, _ in pairs] + [b[1] for _, b in pairs], default=0)
    return max(eu, sig_end), max(el, sig_end)


def header_end(ink, top, bottom, sp):
    return header_glyphs(ink, top, bottom, sp)[0]


def noteheads_fit(ink, staves):
    sp = np.mean([s for _, s in staves])
    holes = ndi.binary_fill_holes(ink) & ~ink
    lab, n = ndi.label(holes)
    hollow_fill = np.zeros_like(ink)
    t = max(2, int(round(0.2 * sp)))
    H, W = ink.shape
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        hh, hw = y1 - y0, x1 - x0
        area = (lab[sl] == i).sum()
        if not (0.04 * sp * sp <= area <= 0.6 * sp * sp and 0.25 * sp <= hw <= HOLE_W * sp and hh <= 0.95 * sp):
            continue
        mid = slice(y0 + hh // 4, max(y0 + hh // 4 + 1, y1 - hh // 4))
        left = ink[mid, max(0, x0 - t):x0].mean() if x0 >= t else 0
        right = ink[mid, x1:min(W, x1 + t)].mean() if x1 + t <= W else 0
        # Ellipse-like (not a rectangle boxed in by lines, stems and barlines), walled on both sides.
        if (not WALLS or (left >= WALL and right >= WALL)) and area / (hw * hh) <= RATIO:
            hollow_fill[sl] |= lab[sl] == i
    closed_fill = np.zeros_like(ink)
    core_ink = np.ones(ink.shape, np.float32)
    solid = (ink | hollow_fill).astype(np.float32)
    score = np.zeros_like(solid)
    for sx in (1.0, 1.3):  # black/half noteheads, and the wider whole notes
        k = ellipse_kernel_xy(sp, 0.9 * sx, 0.9)
        fill = fftconvolve(solid, k[::-1, ::-1].astype(np.float32), mode="same") / k.sum()
        inner = ndi.binary_dilation(ellipse_kernel_xy(sp, sx, 1.0), iterations=1)
        big = ndi.binary_dilation(inner, iterations=max(2, int(0.3 * sp)))
        ring = big & ~inner
        around = fftconvolve(solid, ring[::-1, ::-1].astype(np.float32), mode="same") / ring.sum()
        # In a chord of stacked thirds the heads touch above and below: then judge by the ring's
        # sides alone.
        R = ring.shape[1] // 2
        sides = ring.copy(); sides[:, R - int(0.45 * sp * sx):R + int(0.45 * sp * sx) + 1] = False
        beside = fftconvolve(solid, sides[::-1, ::-1].astype(np.float32), mode="same") / sides.sum()
        ok = (fill >= 0.88) & ((around <= 0.55) | ((beside <= 0.35) & (fill >= 0.92)))
        score = np.maximum(score, np.where(ok, fill - 0.5 * np.minimum(around, 0.55), 0))
    # Not a notehead if ink continues straight above and below it (thick barlines, clef stems).
    d = int(round(1.1 * sp)); c = max(1, int(0.12 * sp))
    up = np.zeros_like(solid); up[d:] = solid[:-d]
    down = np.zeros_like(solid); down[:-d] = solid[d:]
    vertical = ndi.minimum_filter(up, size=(1, 2 * c + 1)) * ndi.minimum_filter(down, size=(1, 2 * c + 1))
    score[vertical > 0] = 0
    # Non-maximum suppression over a notehead-sized window.
    peaks = (score == ndi.maximum_filter(score, size=(int(0.8 * sp), int(1.1 * sp)))) & (score > 0)
    ys, xs = np.nonzero(peaks)
    out, taken = [], []
    for y, x in sorted(zip(ys, xs), key=lambda p: -score[p]):
        if any(abs(x - tx) < 0.9 * sp and abs(y - ty) < 0.7 * sp for tx, ty in taken):
            continue
        enclosed = (hollow_fill & ~closed_fill)[max(0, y - 2):y + 3, max(0, x - 2):x + 3].any()
        if core_ink[y, x] < 0.8 and not enclosed and core_ink[y, x] < 0.35:
            continue
        taken.append((x, y))
        filled = not hollow_fill[max(0, y - 2):y + 3, max(0, x - 2):x + 3].any()
        out.append((float(x), float(y), 1.25 * sp, 0.95 * sp, bool(filled)))
    return split_chords(solid > 0, out, sp)


def split_chords(solid, heads, sp):
    """Stacked chord heads (thirds) touch and read as one tall blob, where the ellipse fit finds
    heads at the wrong heights or misses one: count the heads from the blob's height instead."""
    H, W = solid.shape
    half = int(round(0.6 * sp))
    need = 0.75 * sp
    def wide(y, x):
        return solid[y, max(0, x - half):min(W, x + half + 1)].sum() >= need
    def spans(y, x):  # ink right across, beyond a head on both sides: a staff line or a beam
        return solid[y, max(0, x - 2 * half)] and solid[y, min(W - 1, x + 2 * half)]
    thin = max(1, int(round(0.25 * sp)))
    def grow(y, x, d):
        run = 0
        while 0 <= y + d < H and wide(y + d, x):
            y += d
            run = run + 1 if spans(y, x) else 0
            if run > thin:  # a beam, not a line through the chord
                return y - d * run
        return y - d * run if run else y
    out, done = [], []
    for h in sorted(heads, key=lambda h: h[1]):
        x, y = int(round(h[0])), int(round(h[1]))
        if any(abs(x - dx) < 0.9 * sp and t <= y <= b for dx, t, b in done):
            continue
        top, bot = grow(y, x, -1), grow(y, x, 1)
        n = int(round((bot - top + 1) / sp))
        group = [g for g in heads if abs(g[0] - h[0]) < 0.9 * sp and top - 2 <= g[1] <= bot + 2]
        if n <= 1 or n == len(group) and all(abs(g[1] - (top + (bot - top + 1) * (i + 0.5) / n)) < 0.25 * sp
                                             for i, g in enumerate(sorted(group, key=lambda g: g[1]))):
            out.extend(group if n > 1 else [h])
            done.append((x, top, bot) if n > 1 else (x, y, y))
            continue
        out = [o for o in out if not (abs(o[0] - h[0]) < 0.9 * sp and top - 2 <= o[1] <= bot + 2)]
        step = (bot - top + 1) / n
        for i in range(n):
            out.append((h[0], top + step * (i + 0.5), h[2], h[3], h[4]))
        done.append((x, top, bot))
    return sorted(out)


def read_pitches_fit(path, clefs=("treble", "treble")):
    ink = load(path)
    staves = staff_lines(ink)
    if len(staves) > 2:
        staves = max(((staves[i], staves[i + 1]) for i in range(len(staves) - 1)),
                     key=lambda p: -abs((p[1][0][0] - p[0][0][4]) - 2.5 * p[0][1]))
    upper, lower = staves[0], staves[1]
    split = (upper[0][4] + lower[0][0]) / 2
    hu, hl = header_ends(ink, upper, lower)
    starts = {"upper": hu, "lower": hl}
    result = {"upper": [], "lower": [], "staves": [upper, lower]}
    for x, y, w, h, filled in sorted(noteheads_fit(ink, [upper, lower])):
        name, (ys, sp), clef = ("upper", upper, clefs[0]) if y < split else ("lower", lower, clefs[1])
        if x < starts[name]:
            continue
        exact = (ys[4] - y) / (sp / 2)
        pos = int(round(exact))
        if not -5 <= pos <= 13 or not has_ledgers(ink, x, w, ys[4], sp, pos):
            continue
        result[name].append({"x": x, "y": y, "position": pos, "pitch": pitch_name(clef, pos), "filled": filled,
                             "offset": round(exact - pos, 2)})
    return result


def barlines(ink, upper, lower):
    """x of each barline running from the upper staff's top line to the lower staff's bottom line."""
    top, bottom = int(upper[0][0]), int(lower[0][4])
    cover = ink[top:bottom + 1].mean(0)
    cols = np.nonzero(cover >= 0.9)[0]
    groups, xs = [], []
    for c in cols:
        if groups and c - groups[-1][-1] <= 2:
            groups[-1].append(c)
        else:
            groups.append([c])
    sp = upper[1]
    for g in groups:  # a thin+thick final barline counts once
        x = (g[0] + g[-1]) / 2
        if xs and x - xs[-1] < 1.2 * sp:
            xs[-1] = x
        else:
            xs.append(x)
    return xs


def read_system(path, clefs=("treble", "treble")):
    r = read_pitches_fit(path, clefs)
    ink = load(path)
    r["barlines"] = barlines(ink, *r["staves"])
    return r


def bar_bounds(ink, r):
    """Bar edges: where the music starts (after clef and time signature), each barline after it,
    and the end of the staff if the system doesn't end on a barline."""
    upper, lower = r["staves"]
    sp = upper[1]
    start = min(header_ends(ink, upper, lower))
    rows = [int(round(y)) for y in upper[0]]
    lined = (ink[rows].sum(0) >= 4)
    right = int(np.nonzero(lined)[0].max())
    xs = [x for x in barlines(ink, upper, lower) if x > start + sp]
    bounds = [start] + xs
    if bounds[-1] < right - 1.5 * sp:
        bounds.append(right)
    return bounds


def read_system(path, clefs=("treble", "treble")):
    r = read_pitches_fit(path, clefs)
    ink = load(path)
    r["barlines"] = bar_bounds(ink, r)
    sp = r["staves"][0][1]
    for staff in ("upper", "lower"):  # drop "heads" sitting on a barline
        r[staff] = [h for h in r[staff] if min(abs(h["x"] - b) for b in r["barlines"]) > 0.7 * sp]
    return r


def outline_cover(ink, x, y, sp, n=16):
    """Share of directions from (x, y) that meet ink within a notehead's outline: a hollow head
    is walled all round, a gap that closing filled between a slur and a head is open on a side."""
    t = np.radians(20)
    hit = 0
    for k in range(n):
        a = 2 * np.pi * k / n
        found = False
        for r in np.linspace(0.35, 1.15, 9):
            u, v = 0.62 * sp * r * np.cos(a), 0.46 * sp * r * np.sin(a)
            px = int(round(x + u * np.cos(t) - v * np.sin(t))); py = int(round(y + u * np.sin(t) + v * np.cos(t)))
            if 0 <= py < ink.shape[0] and 0 <= px < ink.shape[1] and ink[py, px]:
                found = True; break
        hit += found
    return hit / n
