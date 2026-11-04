#!/usr/bin/env python3
"""Builds a benchmark for the microphone note detector.

Renders MIDI through a sampled piano (FluidSynth + a General MIDI SoundFont), then makes it
sound like a phone or laptop mic in a room: reverb, background noise, rumble and a random gain.
Each case is written as <name>.wav, <name>.truth.mid (what was played) and <name>.guide.mid
(the score the player follows; differs from the truth in the wrong-note cases).

Usage:
  python3 scripts/make_detector_bench.py OUT_DIR [--soundfont /usr/share/sounds/sf2/FluidR3_GM.sf2]
  then: for c in OUT_DIR/*.wav; do swift run -c release grade listen "$c" \
          --truth "${c%.wav}.truth.mid" --guide "${c%.wav}.guide.mid" --offset 0.5; done

Needs fluidsynth, numpy, scipy and mido. Cases are reproducible (fixed random seeds).
"""
import argparse, os, random, subprocess, sys, wave
import numpy as np
import mido
from scipy.signal import fftconvolve, butter, lfilter

RATE = 48000
PAD = 0.5  # seconds of silence before the music (pass --offset 0.5 to grade listen)


def write_midi(path, notes, bpm=96, tpq=480):
    """notes: (start_beats, length_beats, pitch, velocity)"""
    mid = mido.MidiFile(ticks_per_beat=tpq)
    tr = mido.MidiTrack(); mid.tracks.append(tr)
    tr.append(mido.MetaMessage('set_tempo', tempo=mido.bpm2tempo(bpm), time=0))
    ev = []
    for s, l, p, v in notes:
        ev.append((int(round(s * tpq)), 1, p, v))
        ev.append((int(round((s + l) * tpq)), 0, p, 0))
    ev.sort(key=lambda e: (e[0], e[1]))
    last = 0
    for t, on, p, v in ev:
        tr.append(mido.Message('note_on' if on else 'note_off', note=p, velocity=v if on else 0, time=t - last))
        last = t
    mid.save(path)


def midi_notes(path):
    mid = mido.MidiFile(path)
    out, held, t = [], {}, 0.0
    for msg in mid:  # merged, times in seconds
        t += msg.time
        if msg.type == 'note_on' and msg.velocity > 0 and getattr(msg, 'channel', 0) != 9:
            held.setdefault(msg.note, []).append((t, msg.velocity))
        elif msg.type in ('note_off', 'note_on') and getattr(msg, 'channel', 0) != 9 and held.get(msg.note):
            s, v = held[msg.note].pop(0)
            out.append((s, t - s, msg.note, v))
    return out


def render(midi_path, sf2, wav_path):
    raw = wav_path + '.raw.wav'
    subprocess.run(['fluidsynth', '-ni', '-g', '0.7', '-R', '0', '-C', '0', '-r', str(RATE), '-F', raw, sf2, midi_path],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with wave.open(raw) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        data = data.reshape(-1, w.getnchannels()).mean(axis=1)
    os.remove(raw)
    return data


def room(x, rng, rt60, noise_db, gain_db):
    # Exponentially decaying noise as a room impulse response, mixed with the direct sound.
    n = int(rt60 * RATE)
    if n > 0:
        t = np.arange(n) / RATE
        ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
        ir[:int(0.003 * RATE)] = 0
        ir *= 0.25 / np.sqrt(np.sum(ir ** 2))
        ir[0] = 1.0
        x = fftconvolve(x, ir)[:len(x) + n // 4]
    # Small-mic tilt: a little low cut and some rumble.
    b, a = butter(2, 70 / (RATE / 2), 'high')
    x = lfilter(b, a, x)
    rumble = lfilter(*butter(2, 120 / (RATE / 2), 'low'), rng.standard_normal(len(x))) * 10 ** ((noise_db + 6) / 20)
    hiss = rng.standard_normal(len(x)) * 10 ** (noise_db / 20)
    x = x * 10 ** (gain_db / 20) + rumble + hiss
    return np.clip(x, -1, 1).astype(np.float32)


def write_wav(path, x):
    pad = np.zeros(int(PAD * RATE), dtype=np.float32)
    y = np.concatenate([pad, x])
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


def beginner_piece(rng, low=55, high=79, bars=8, chords=True):
    """Melody in quarters/halves/eighths around C major-ish, with some chords and repeated notes."""
    scale = [0, 2, 4, 5, 7, 9, 11]
    notes, beat, p = [], 0.0, 67
    while beat < bars * 4:
        length = rng.choice([1, 1, 1, 2, 0.5, 0.5])
        step = rng.choice([-2, -1, -1, 0, 1, 1, 2, 3, -3])
        degree = scale.index(min(scale, key=lambda s: abs(s - p % 12))) + step
        p = (p // 12) * 12 + scale[degree % 7] + 12 * (degree // 7)
        p = max(low, min(high, p))
        vel = rng.randint(45, 100)
        notes.append((beat, length * 0.95, p, vel))
        if chords and rng.random() < 0.18:
            for d in rng.choice([[4], [3, 7], [-5], [-8, -12]]):
                if 36 <= p + d <= 96:
                    notes.append((beat, length * 0.95, p + d, vel - 10))
        beat += length
    return notes


def with_mistakes(notes, rng, rate=0.2):
    """Performance with mistakes: neighbour-key substitutions and extra keys struck alongside."""
    out = []
    for s, l, p, v in notes:
        r = rng.random()
        if r < rate / 2:
            out.append((s, l, p + rng.choice([-2, -1, 1, 2]), v))         # wrong key instead
        elif r < rate:
            out.append((s, l, p, v))
            out.append((s + rng.uniform(0, 0.02), l, p + rng.choice([-1, 1, 2]), v))  # extra key with it
        else:
            out.append((s, l, p, v))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--soundfont', default='/usr/share/sounds/sf2/FluidR3_GM.sf2')
    ap.add_argument('--examples', default=os.path.join(os.path.dirname(__file__), '..', 'Examples'))
    ap.add_argument('--extra-midi', nargs='*', default=[])
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(7)
    nrng = np.random.default_rng(7)

    cases = []  # (name, truth notes(seconds), guide notes(seconds))
    for f in ['five-finger.mid', 'mary-had-a-little-lamb.mid', 'ode-to-joy-c.mid'] + args.extra_midi:
        path = f if os.path.isabs(f) else os.path.join(args.examples, f)
        n = midi_notes(path)
        cases.append((os.path.splitext(os.path.basename(path))[0], n, n))
    spb = 60 / 96
    for i in range(4):
        piece = [(s * spb, l * spb, p, v) for s, l, p, v in beginner_piece(rng, chords=i % 2 == 0)]
        cases.append((f'random{i}', piece, piece))
        wrong = with_mistakes(piece, rng)
        cases.append((f'random{i}-mistakes', wrong, piece))
    low = [(s * spb, l * spb, p, v) for s, l, p, v in beginner_piece(rng, low=40, high=60, chords=False)]
    cases.append(('low-register', low, low))

    rooms = [('dry', 0.0, -70, 0), ('room', 0.45, -55, -6), ('noisy', 0.8, -45, -12)]
    for name, truth, guide in cases:
        tmp_truth = os.path.join(args.out, '_tmp.mid')
        write_midi(tmp_truth, [(s / spb, l / spb, p, v) for s, l, p, v in truth])
        audio = render(tmp_truth, args.soundfont, os.path.join(args.out, '_tmp'))
        for rname, rt60, noise, gain in rooms:
            base = os.path.join(args.out, f'{name}.{rname}')
            write_wav(base + '.wav', room(audio, nrng, rt60, noise, gain))
            write_midi(base + '.truth.mid', [(s / spb, l / spb, p, v) for s, l, p, v in truth])
            write_midi(base + '.guide.mid', [(s / spb, l / spb, p, v) for s, l, p, v in guide])
        os.remove(tmp_truth)
    print(f'{len(cases) * len(rooms)} cases in {args.out}')


if __name__ == '__main__':
    main()
