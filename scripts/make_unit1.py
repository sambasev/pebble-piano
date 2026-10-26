#!/usr/bin/env python3
"""Writes the exercise MIDI for Lessons/unit1 (Book 1, Unit 1: Middle C position).

Run from the repository root:  python3 scripts/make_unit1.py
Rewrites every file it owns; the output is deterministic, so a diff shows real changes only.
Each exercise is a list of (note name, length in quarter notes) in 4/4 at 60 bpm, right hand.
No dependencies: a tiny format-0 MIDI writer is below.
"""
import os
import struct

TPQ = 480          # ticks per quarter note
BPM = 60
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Lessons", "unit1")

LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pitch(name):
    """'C4' → 60, 'D#4' → 63, 'Bb3' → 58."""
    base = LETTERS[name[0].upper()]
    i, shift = 1, 0
    while name[i] in "#b":
        shift += 1 if name[i] == "#" else -1
        i += 1
    return (int(name[i:]) + 1) * 12 + base + shift


# ── Exercises ────────────────────────────────────────────────────────────────
# Page 1: Meet Middle C. Notes are a little short of their full length so each
# re-strike is clearly separate when played back.
EXERCISES = {
    # "Play the note C" three times: one whole bar of quarter notes, then a rest.
    "p1-ex1.mid": [("C4", 1), ("C4", 1), ("C4", 1), (None, 1)],
    # Four Cs, then two half notes: still one note, now with longer values.
    "p1-ex2.mid": [("C4", 1), ("C4", 1), ("C4", 1), ("C4", 1), ("C4", 2), ("C4", 2)],
    # The timed exercise: quarters and halves, two bars.
    "p1-ex3.mid": [("C4", 1), ("C4", 1), ("C4", 2), ("C4", 2), ("C4", 2)],

    # Page 2: Meet D (finger 2).
    "p2-ex1.mid": [("D4", 1), ("D4", 1), ("D4", 1), (None, 1)],
    "p2-ex2.mid": [("C4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("C4", 1), ("C4", 1), ("D4", 2)],
    "p2-ex3.mid": [("C4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("D4", 1), ("D4", 1), ("C4", 2)],

    # Page 4: Adding E (finger 3). The timed one is the opening of Mary Had a Little Lamb.
    "p4-ex1.mid": [("E4", 1), ("E4", 1), ("E4", 1), (None, 1)],
    "p4-ex2.mid": [("C4", 1), ("D4", 1), ("E4", 1), ("D4", 1), ("C4", 1), ("E4", 1), ("C4", 2)],
    "p4-ex3.mid": [("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1), ("E4", 2)],

    # Page 5: Meet F (finger 4), the white key just left of the 3 black keys.
    "p5-ex1.mid": [("F4", 1), ("F4", 1), ("F4", 1), (None, 1)],
    "p5-ex2.mid": [("E4", 1), ("F4", 1), ("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("F4", 1)],
    "p5-ex3.mid": [("C4", 1), ("D4", 1), ("E4", 1), ("F4", 1), ("E4", 1), ("D4", 1), ("C4", 2)],

    # Page 6: Meet G (finger 5). The timed one walks all five fingers up and down.
    "p6-ex1.mid": [("G4", 1), ("G4", 1), ("G4", 1), (None, 1)],
    "p6-ex2.mid": [("E4", 1), ("F4", 1), ("G4", 2), ("G4", 1), ("F4", 1), ("E4", 2)],
    "p6-ex3.mid": [("C4", 1), ("D4", 1), ("E4", 1), ("F4", 1), ("G4", 2), ("G4", 2),
                   ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1), ("C4", 2), (None, 2)],
}

# Checkpoint song after the first three notes: Au Clair de la Lune (French traditional,
# public domain), its first phrase twice, C D E only, at 80 bpm.
CHECKPOINTS = {
    "auClairDeLaLune": [
        ("C4", 1), ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 2), ("D4", 2),
        ("C4", 1), ("E4", 1), ("D4", 1), ("D4", 1), ("C4", 4),
    ] * 2,
}

# Goal songs (public domain, right hand, Middle C position). One per GoalSongs ID
# (Sources/PianoLessons/GoalSongs.swift), written to songs/ at 80 bpm.
SONG_BPM = 80
SONGS = {
    "mary": [
        ("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1), ("E4", 2),
        ("D4", 1), ("D4", 1), ("D4", 2), ("E4", 1), ("G4", 1), ("G4", 2),
        ("E4", 1), ("D4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1), ("E4", 1), ("E4", 1),
        ("D4", 1), ("D4", 1), ("E4", 1), ("D4", 1), ("C4", 4),
    ],
    "hotCrossBuns": [
        ("E4", 1), ("D4", 1), ("C4", 2), ("E4", 1), ("D4", 1), ("C4", 2),
        ("C4", 0.5), ("C4", 0.5), ("C4", 0.5), ("C4", 0.5), ("D4", 0.5), ("D4", 0.5), ("D4", 0.5), ("D4", 0.5),
        ("E4", 1), ("D4", 1), ("C4", 2),
    ],
    "odeToJoy": [
        ("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1), ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
        ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("E4", 1.5), ("D4", 0.5), ("D4", 2),
        ("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1), ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
        ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1), ("D4", 1.5), ("C4", 0.5), ("C4", 2),
    ],
    "jingleBells": [
        ("E4", 1), ("E4", 1), ("E4", 2), ("E4", 1), ("E4", 1), ("E4", 2),
        ("E4", 1), ("G4", 1), ("C4", 1.5), ("D4", 0.5), ("E4", 4),
        ("F4", 1), ("F4", 1), ("F4", 1.5), ("F4", 0.5), ("F4", 1), ("E4", 1), ("E4", 1), ("E4", 0.5), ("E4", 0.5),
        ("G4", 1), ("G4", 1), ("F4", 1), ("D4", 1), ("C4", 4),
    ],
}


def varlen(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def track(events, title, bpm):
    """events: [(name or None, quarters)] in order. Returns the MTrk chunk."""
    data = bytearray()
    name = title.encode()
    data += varlen(0) + b"\xff\x03" + varlen(len(name)) + name           # track name
    data += varlen(0) + b"\xff\x51\x03" + struct.pack(">I", 60_000_000 // bpm)[1:]  # tempo
    data += varlen(0) + b"\xff\x58\x04\x04\x02\x18\x08"                  # 4/4
    pending = 0  # ticks since the last event
    for note, quarters in events:
        ticks = int(quarters * TPQ)
        if note is None:
            pending += ticks
            continue
        held = ticks - min(TPQ // 8, ticks // 4)
        data += varlen(pending) + bytes([0x90, pitch(note), 80])
        data += varlen(held) + bytes([0x80, pitch(note), 0])
        pending = ticks - held
    data += varlen(pending) + b"\xff\x2f\x00"                            # end of track
    return b"MTrk" + struct.pack(">I", len(data)) + bytes(data)


def write(filename, events, bpm=BPM):
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, TPQ)
    title = os.path.splitext(os.path.basename(filename))[0]
    with open(os.path.join(OUT, filename), "wb") as f:
        f.write(header + track(events, title, bpm))
    print("wrote", os.path.normpath(os.path.join(OUT, filename)))


def bars_ok(name, events):
    """Every piece fills whole 4/4 bars, so count-ins and bar replays line up."""
    total = sum(q for _, q in events)
    assert total % 4 == 0, f"{name}: {total} quarters is not whole bars"


if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "songs"), exist_ok=True)
    for filename, events in EXERCISES.items():
        bars_ok(filename, events)
        write(filename, events)
    for song, events in CHECKPOINTS.items():
        bars_ok(song, events)
        write(os.path.join("songs", song + ".mid"), events, bpm=SONG_BPM)
    for song, events in SONGS.items():
        bars_ok(song, events)
        write(os.path.join("songs", song + ".mid"), events, bpm=SONG_BPM)
