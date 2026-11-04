"""Minimal Standard MIDI File reader: enough to rebuild the score the tutor sees.

No dependencies. Returns notes as (track, pitch, start_quarter, duration_quarter) plus the
time signature and tempo, so cases can carry ground truth for grounding checks.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import List, Tuple

NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def pitch_name(p: int) -> str:
    return f"{NAMES[p % 12]}{p // 12 - 1}"


@dataclass
class Note:
    track: int
    pitch: int
    start: float  # quarter notes from the start
    duration: float

    @property
    def name(self) -> str:
        return pitch_name(self.pitch)


@dataclass
class MidiScore:
    notes: List[Note]
    numerator: int = 4
    denominator: int = 4
    bpm: float = 120.0
    tracks_with_notes: int = 0
    bars: List[List[Note]] = field(default_factory=list)

    @property
    def bar_quarters(self) -> float:
        return self.numerator * 4 / self.denominator


def _varlen(data: bytes, i: int) -> Tuple[int, int]:
    v = 0
    while True:
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80:
            return v, i


def read(path: str) -> MidiScore:
    data = open(path, "rb").read()
    if data[:4] != b"MThd":
        raise ValueError(f"{path}: not a MIDI file")
    _, ntracks, division = struct.unpack(">HHH", data[8:14])
    i = 14
    notes: List[Note] = []
    num, den, bpm = 4, 4, 120.0
    for t in range(ntracks):
        assert data[i:i + 4] == b"MTrk", "bad track chunk"
        length = struct.unpack(">I", data[i + 4:i + 8])[0]
        j, end = i + 8, i + 8 + length
        tick, status, on = 0, 0, {}
        while j < end:
            delta, j = _varlen(data, j)
            tick += delta
            b = data[j]
            if b == 0xFF:
                kind = data[j + 1]
                ln, k = _varlen(data, j + 2)
                body = data[k:k + ln]
                if kind == 0x58 and tick == 0:
                    num, den = body[0], 2 ** body[1]
                elif kind == 0x51 and tick == 0:
                    bpm = 60_000_000 / int.from_bytes(body, "big")
                j = k + ln
                continue
            if b in (0xF0, 0xF7):
                ln, k = _varlen(data, j + 1)
                j = k + ln
                continue
            if b & 0x80:
                status = b
                j += 1
            hi = status & 0xF0
            if hi in (0xC0, 0xD0):
                j += 1
                continue
            d1, d2 = data[j], data[j + 1]
            j += 2
            if hi == 0x90 and d2 > 0:
                on[d1] = tick
            elif hi == 0x80 or (hi == 0x90 and d2 == 0):
                if d1 in on:
                    s = on.pop(d1)
                    notes.append(Note(t, d1, s / division, (tick - s) / division))
        i = end
    notes.sort(key=lambda n: (n.start, n.pitch))
    score = MidiScore(notes, num, den, round(bpm, 1))
    score.tracks_with_notes = len({n.track for n in notes})
    if notes:
        last = max(n.start + n.duration for n in notes)
        count = int(-(-round(last, 3) // score.bar_quarters))
        score.bars = [[] for _ in range(count)]
        for n in notes:
            score.bars[int(n.start // score.bar_quarters + 1e-6)].append(n)
    return score
