#!/usr/bin/env python3
"""Turns a reading of Beyer Op. 101 into reference MIDI for grading.

    python3 scripts/reading_to_midi.py                 # Muse Wonder's readings and the hand-checked truth
    python3 scripts/reading_to_midi.py --bpm 72

Reads .build/ai-probe2/<model>-<crop>.json (from ai_probe2.py) and Fixtures/beyer/truth/pieces.json.
Writes Fixtures/beyer/midi/<piece>-<source>.mid (both hands, one track per hand) plus
-rh / -lh files for hands-separate practice. 4/4, notes held a little short of full length so
repeated notes re-strike, the same as scripts/make_unit1.py.
"""
import argparse, json, os, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from ai_probe2 import pitch as position_to_name  # noqa: E402

TPQ = 480
QUARTERS = {"whole": 4, "half": 2, "quarter": 1, "eighth": 0.5, "sixteenth": 0.25}
LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ACCIDENTAL = {"none": 0, "natural": 0, "sharp": 1, "flat": -1}


def midi_number(name, shift=0):
    return (int(name[1:]) + 1) * 12 + LETTERS[name[0]] + shift


def quarters(duration):
    d = duration.rstrip(".")
    return QUARTERS[d] * (1.5 if duration.endswith(".") else 1)


def varlen(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def track(events, title, bpm=None, channel=0):
    """events: [(midi number or None, quarters)]."""
    d = bytearray()
    d += varlen(0) + b"\xff\x03" + varlen(len(title)) + title.encode()
    if bpm:
        d += varlen(0) + b"\xff\x51\x03" + struct.pack(">I", 60_000_000 // bpm)[1:]
        d += varlen(0) + b"\xff\x58\x04\x04\x02\x18\x08"
    pending = 0
    for note, q in events:
        ticks = int(q * TPQ)
        if note is None:
            pending += ticks
            continue
        held = ticks - min(TPQ // 8, ticks // 4)
        d += varlen(pending) + bytes([0x90 | channel, note, 80])
        d += varlen(held) + bytes([0x80 | channel, note, 0])
        pending = ticks - held
    d += varlen(pending) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(d)) + bytes(d)


def write(path, hands, bpm, title):
    """hands: list of (name, events). Format 1, the first track carries tempo and metre."""
    chunks = [track(ev, f"{title} {name}", bpm if i == 0 else None, channel=i) for i, (name, ev) in enumerate(hands)]
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), TPQ) + b"".join(chunks))


def from_truth(measures, staff):
    return [(None if n == "r" else midi_number(n), quarters(d)) for m in measures for n, d in m[staff]]


def from_reading(readings, staff):
    out = []
    for r in readings:
        for m in r["measures"]:
            s = m[staff]
            for n in s["notes"]:
                if n["rest"]:
                    out.append((None, quarters(n["duration"] + ("." if n["dotted"] else ""))))
                else:
                    name = position_to_name(s["clef"], n["position"])
                    out.append((midi_number(name, ACCIDENTAL[n["accidental"]]),
                                quarters(n["duration"] + ("." if n["dotted"] else ""))))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="muse-wonder-1.0")
    ap.add_argument("--bpm", type=int, default=80)
    a = ap.parse_args()
    truth = json.load(open(os.path.join(ROOT, "Fixtures", "beyer", "truth", "pieces.json")))
    out_dir = os.path.join(ROOT, "Fixtures", "beyer", "midi")
    os.makedirs(out_dir, exist_ok=True)
    for piece, t in truth.items():
        sources = {"truth": (from_truth(t["measures"], "upper"), from_truth(t["measures"], "lower"))}
        paths = [os.path.join(ROOT, ".build", "ai-probe2", f"{a.model}-{c}.json") for c in t["crops"]]
        if all(os.path.exists(p) for p in paths):
            readings = [json.load(open(p)) for p in paths]
            sources[a.model.split("-")[1]] = (from_reading(readings, "upper"), from_reading(readings, "lower"))
        for source, (rh, lh) in sources.items():
            for bad in (rh, lh):
                total = sum(q for _, q in bad)
                if total % 4:
                    print(f"  warning: {piece}-{source} has {total} quarters, not whole 4/4 bars")
            base = os.path.join(out_dir, f"beyer-{piece}-{source}")
            write(base + ".mid", [("RH", rh), ("LH", lh)], a.bpm, f"Beyer {piece}")
            write(base + "-rh.mid", [("RH", rh)], a.bpm, f"Beyer {piece}")
            write(base + "-lh.mid", [("LH", lh)], a.bpm, f"Beyer {piece}")
            print("wrote", os.path.relpath(base, ROOT) + "{,-rh,-lh}.mid")


if __name__ == "__main__":
    main()
