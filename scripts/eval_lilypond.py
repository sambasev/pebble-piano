"""Scores the geometry reader against LilyPond's MIDI for a folder of engraved pages.

usage: python3 scripts/eval_lilypond.py .build/private-books/out [name-filter]
(scripts/private_books.sh makes that folder.) For each piece, compares the pitches measured on
each staff, system by system, with the MIDI's two tracks (longest common subsequence). Notes
read but not in the MIDI that repeat their neighbour are counted as ties, not errors: MIDI
sounds a tied note once.
Private test only: the engraved pieces are not ours to ship. Needs numpy scipy pillow mido.
"""
import sys, os, glob, json, re
from collections import Counter
import numpy as np
import mido
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(__file__))
import notehead_geometry as G  # scripts/notehead_geometry.py

DIAT = [0, 2, 4, 5, 7, 9, 11]


def midi_of(clef, pos):
    i = G.BOTTOM_LINE[clef] + pos
    return 12 * (i // 7 + 1) + DIAT[i % 7]


# ── clef kind ────────────────────────────────────────────────────────────────
def clef_of(ink, top, bottom, sp):
    """('treble'|'bass', x end) for the clef at the start of a staff, or (None, 0)."""
    y0 = max(0, int(top - 3 * sp))
    band = G.without_lines(ink, sp)[y0:int(bottom + 3 * sp)]
    lab, n = ndi.label(band)
    W = ink.shape[1]
    best = None
    for sl in ndi.find_objects(lab):
        x0, x1 = sl[1].start, sl[1].stop
        ya, yb = sl[0].start + y0, sl[0].stop + y0
        h, w = yb - ya, x1 - x0
        if x0 > 0.3 * W or not 1.5 * sp <= w <= 6 * sp:
            continue
        if h >= 4.5 * sp:
            kind = "treble"
        # The bass clef: ~3 spaces tall, hanging from the top line.
        elif 2.4 * sp <= h <= 4.2 * sp and abs(ya - top) <= 0.8 * sp and yb <= bottom + 0.6 * sp:
            kind = "bass"
        else:
            continue
        if best is None or x0 < best[1]:
            best = (kind, x0, x1)
    return (best[0], best[2]) if best else (None, 0)


# ── systems on a page ────────────────────────────────────────────────────────
def systems(ink):
    staves = G.staff_lines(ink)
    if not staves:
        return []
    med = np.median([s for _, s in staves])
    staves = [s for s in staves if abs(s[1] - med) <= 0.25 * med]
    out, i = [], 0
    while i + 1 < len(staves):
        a, b = staves[i], staves[i + 1]
        gap = b[0][0] - a[0][4]
        nxt = staves[i + 2][0][0] - b[0][4] if i + 2 < len(staves) else 1e9
        if gap > 1.3 * nxt or gap > 12 * med:
            i += 1; continue
        out.append((a, b)); i += 2
    sp = med
    crops = []
    for k, (a, b) in enumerate(out):
        top = a[0][0] - 3.5 * sp
        bot = b[0][4] + 3.5 * sp
        if k > 0:
            top = max(top, (out[k - 1][1][0][4] + a[0][0]) / 2)
        if k + 1 < len(out):
            bot = min(bot, (b[0][4] + out[k + 1][0][0][0]) / 2)
        crops.append((int(max(0, top)), int(min(ink.shape[0], bot))))
    return crops


def read_crop(ink):
    staves = G.staff_lines(ink)
    if len(staves) < 2:
        return None
    upper, lower = staves[0], staves[1]
    sp = upper[1]
    cu, eu = clef_of(ink, upper[0][0], upper[0][4], sp)
    cl, el = clef_of(ink, lower[0][0], lower[0][4], sp)
    split = (upper[0][4] + lower[0][0]) / 2
    hu, hl = G.header_ends(ink, upper, lower)
    starts = {"upper": max(hu, eu), "lower": max(hl, el)}
    clefs = {"upper": cu or "treble", "lower": cl or "treble"}
    res = {"upper": [], "lower": [], "clefs": (cu, cl)}
    for x, y, w, h, filled in sorted(G.noteheads_fit(ink, [upper, lower])):
        name, (ys, s) = ("upper", upper) if y < split else ("lower", lower)
        if x < starts[name]:
            continue
        exact = (ys[4] - y) / (s / 2)
        pos = int(round(exact))
        if not -5 <= pos <= 13 or not G.has_ledgers(ink, x, w, ys[4], s, pos):
            continue
        res[name].append((x, y, midi_of(clefs[name], pos), filled, round(exact - pos, 2)))
    # drop heads on barlines
    try:
        bars = G.barlines(ink, upper, lower)
    except Exception:
        bars = []
    for k in ("upper", "lower"):
        res[k] = [n for n in res[k] if not bars or min(abs(n[0] - b) for b in bars) > 0.7 * sp]
    return res


def read_page(path):
    ink = G.load(path)
    out = []
    for t, b in systems(ink):
        r = read_crop(ink[t:b])
        if r:
            out.append(r)
    return out


# ── truth ────────────────────────────────────────────────────────────────────
def midi_tracks(path):
    mf = mido.MidiFile(path)
    tracks = []
    for tr in mf.tracks:
        t, on, notes = 0, {}, []
        for m in tr:
            t += m.time
            if m.type == "note_on" and m.velocity > 0:
                notes.append((t, m.note))
        if notes:
            tracks.append(sorted(notes))
    return tracks


def seq(notes):
    """Chord notes ordered low→high within each onset."""
    return [n for _, n in sorted(notes)]


def lcs(a, b):
    n, m = len(a), len(b)
    d = np.zeros((n + 1, m + 1), int)
    for i in range(n):
        for j in range(m):
            d[i + 1, j + 1] = d[i, j] + 1 if a[i] == b[j] else max(d[i, j + 1], d[i + 1, j])
    return int(d[n, m])


def unmatched_repeats(a, b):
    """Read notes left unmatched that repeat the note before them: ties (MIDI sounds a tied note once)."""
    n, m = len(a), len(b)
    d = np.zeros((n + 1, m + 1), int)
    for i in range(n):
        for j in range(m):
            d[i + 1, j + 1] = d[i, j] + 1 if a[i] == b[j] else max(d[i, j + 1], d[i + 1, j])
    i, j, rep = n, m, 0
    while i > 0 and j > 0:
        if a[i - 1] == b[j - 1]:
            i -= 1; j -= 1
        elif d[i - 1, j] >= d[i, j - 1]:
            rep += (i > 1 and a[i - 1] == a[i - 2]) or (i < n and a[i - 1] == a[i]); i -= 1
        else:
            j -= 1
    while i > 0:
        rep += (i > 1 and a[i - 1] == a[i - 2]) or (i < n and a[i - 1] == a[i]); i -= 1
    return rep


def read_order(heads):
    """Group heads into onsets by x, low→high pitch within an onset."""
    heads = sorted(heads)
    groups = []
    for h in heads:
        if groups and h[0] - groups[-1][-1][0] < 6:
            groups[-1].append(h)
        else:
            groups.append([h])
    return [n[2] for g in groups for n in sorted(g, key=lambda n: n[2])]


def main():
    d = sys.argv[1]
    filt = sys.argv[2] if len(sys.argv) > 2 else ""
    total = Counter()
    rows = []
    for midi in sorted(glob.glob(os.path.join(d, "*.midi"))):
        name = os.path.basename(midi)[:-5]
        if filt not in name:
            continue
        pages = sorted(glob.glob(os.path.join(d, name + ".png")) + glob.glob(os.path.join(d, name + "-page*.png")),
                       key=lambda p: int(re.findall(r"(\d+)\.png$", p)[0]) if "-page" in p else 0)
        tr = midi_tracks(midi)
        if len(tr) < 2:
            rows.append((name, "skip", len(tr))); continue
        sysr = [r for p in pages for r in read_page(p)]
        got = {k: [p for r in sysr for p in read_order(r[k])] for k in ("upper", "lower")}
        want = {"upper": seq(tr[0]), "lower": seq(tr[1])}
        clefs = Counter(c for r in sysr for c in r["clefs"])
        rec = {}
        for k in ("upper", "lower"):
            m = lcs(got[k], want[k])
            tie = unmatched_repeats(got[k], want[k])
            rec[k] = (m, len(got[k]) - tie, len(want[k]))
            total["ties"] += tie
            total["match"] += m; total["read"] += len(got[k]) - tie; total["truth"] += len(want[k])
        exact = all(r[0] == r[1] == r[2] for r in rec.values())
        total["pieces"] += 1; total["exact"] += exact
        rows.append((name, len(sysr), dict(clefs), rec, exact))
        print(name[:40], len(sysr), dict(clefs), rec, "OK" if exact else "", flush=True)
    print(json.dumps(total))
    print("recall %.4f precision %.4f" % (total["match"] / max(1, total["truth"]), total["match"] / max(1, total["read"])))


if __name__ == "__main__":
    main()
