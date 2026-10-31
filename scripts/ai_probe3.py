#!/usr/bin/env python3
"""Hackathon probe 3: Muse Wonder's reading (rhythm, structure) + measured pitch, per bar.

For each bar and staff: if the number of noteheads found in the image equals the number of
notes the model read, each note's pitch comes from its measured height (or the bar is flagged
when a head sits between a line and a space). Otherwise the bar is flagged as unverified and
keeps the model's pitches. Scored against Fixtures/beyer/truth/pieces.json. No API calls: it
reuses the readings saved by ai_probe2.py.

    python3 -m pip install numpy scipy pillow     # once
    python3 scripts/ai_probe3.py                   # scan crops and modern images
    python3 scripts/ai_probe3.py --draw            # also writes overlays to .build/ai-probe3/
"""
import argparse, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from notehead_geometry import read_system  # noqa: E402
from ai_probe2 import pitch as model_pitch  # noqa: E402

FIX = os.path.join(ROOT, "Fixtures", "beyer")
CROPS = {"no12": ["no12"], "no13": ["no13"], "no24": ["no24a", "no24b"]}
SOURCES = {"scan": (os.path.join(FIX, "crops"), os.path.join(ROOT, ".build", "ai-probe2")),
           "modern": (os.path.join(FIX, "modern"), os.path.join(ROOT, ".build", "ai-probe2", "modern"))}
OUT = os.path.join(ROOT, ".build", "ai-probe3")


def merge_system(reading, geo):
    xs = geo["barlines"]
    same_bars = len(xs) - 1 == len(reading["measures"])
    out = []
    for i, m in enumerate(reading["measures"]):
        bar = {"status": {}}
        for staff in ("upper", "lower"):
            s = m[staff]
            notes = [[("r" if n["rest"] else model_pitch(s["clef"], n["position"])),
                      n["duration"] + ("." if n["dotted"] else "")] for n in s["notes"]]
            sounding = [k for k, n in enumerate(notes) if n[0] != "r"]
            if not same_bars:
                status = "unverified: bar count differs"
            else:
                heads = [h for h in geo[staff] if xs[i] < h["x"] < xs[i + 1]]
                if len(heads) != len(sounding):
                    status = f"unverified: {len(heads)} heads found, model read {len(sounding)} notes"
                else:
                    changed = unsure = 0
                    for k, h in zip(sounding, heads):
                        if notes[k][0] != h["pitch"]:
                            if abs(h["offset"]) > 0.3:  # between a line and a space: don't trust it
                                unsure += 1
                            else:
                                notes[k][0] = h["pitch"]; changed += 1
                    status = (f"unverified: {unsure} unclear heads" if unsure else
                              f"corrected {changed}" if changed else "confirmed")
            bar[staff] = notes
            bar["status"][staff] = status
        out.append(bar)
    return out


def draw(path, geo, out_path):
    from PIL import Image, ImageDraw
    im = Image.open(path).convert("RGB")  # overlay is on the original; deskew is tiny
    d = ImageDraw.Draw(im)
    for x in geo["barlines"]:
        d.line((x, 0, x, im.height), fill=(0, 120, 255), width=2)
    for staff in ("upper", "lower"):
        for h in geo[staff]:
            c = (0, 170, 0) if abs(h["offset"]) <= 0.3 else (255, 140, 0)
            d.ellipse((h["x"] - 9, h["y"] - 9, h["x"] + 9, h["y"] + 9), outline=c, width=3)
            d.text((h["x"] - 7, h["y"] + 11), h["pitch"], fill=(200, 0, 200))
    im.save(out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="muse-wonder-1.0")
    ap.add_argument("--draw", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    truth = json.load(open(os.path.join(FIX, "truth", "pieces.json")))
    report = []
    for src, (img_dir, read_dir) in SOURCES.items():
        tot = {"model": 0, "merged": 0, "notes": 0, "trusted": 0, "bars": 0, "silent": 0}
        for piece, crops in CROPS.items():
            bars = []
            for c in crops:
                rp = os.path.join(read_dir, f"{a.model}-{c}.json")
                if not os.path.exists(rp):
                    print(f"skip {src} {c}: no reading at {rp} (run ai_probe2.py first)"); break
                reading = json.load(open(rp))
                geo = read_system(os.path.join(img_dir, c + ".png"))
                if a.draw:
                    draw(os.path.join(img_dir, c + ".png"), geo, os.path.join(OUT, f"{src}-{c}.png"))
                bars += merge_system(reading, geo)
                for m in reading["measures"]:  # the model alone, for comparison
                    m["_notes"] = {s: [["r" if n["rest"] else model_pitch(m[s]["clef"], n["position"]),
                                        n["duration"] + ("." if n["dotted"] else "")] for n in m[s]["notes"]]
                                   for s in ("upper", "lower")}
                bars[-len(reading["measures"]):] = [dict(b, model=m["_notes"]) for b, m in
                                                    zip(bars[-len(reading["measures"]):], reading["measures"])]
            else:
                t = truth[piece]["measures"]
                lines = []
                for i, (b, tm) in enumerate(zip(bars, t)):
                    for s in ("upper", "lower"):
                        n = len(tm[s]); tot["notes"] += n; tot["bars"] += 1
                        tot["merged"] += sum(1 for j, x in enumerate(tm[s]) if j < len(b[s]) and b[s][j] == x)
                        tot["model"] += sum(1 for j, x in enumerate(tm[s]) if j < len(b["model"][s]) and b["model"][s][j] == x)
                        st = b["status"][s]
                        if st.startswith("unverified"):
                            lines.append(f"   bar {i + 1} {s}: {st}")
                        else:
                            tot["trusted"] += 1
                            if b[s] != tm[s]:
                                tot["silent"] += 1
                                lines.append(f"   SILENT ERROR bar {i + 1} {s}: {b[s]} vs truth {tm[s]}")
                report.append(f"{src} {piece}"); report += lines
        line = (f"{src}: model alone {tot['model']}/{tot['notes']} notes, with measured pitch "
                f"{tot['merged']}/{tot['notes']} ({100 * tot['merged'] / max(1, tot['notes']):.0f}%); "
                f"bars trusted {tot['trusted']}/{tot['bars']}; silent errors {tot['silent']}")
        report.append(line)
        print(line)
    open(os.path.join(OUT, "report.txt"), "w").write("\n".join(report) + "\n")
    print("Details in", os.path.join(OUT, "report.txt"))


if __name__ == "__main__":
    main()
