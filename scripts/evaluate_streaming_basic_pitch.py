#!/usr/bin/env python3
"""
Evaluate Streaming FIFO Ring-Buffer & Immediate Note-On Dispatch for Spotify Basic Pitch.

Simulates a real-time interactive audio pipeline:
- A 43,844-sample (~1.988s @ 22,050 Hz) FIFO ring buffer.
- Streaming audio arrives in hops (1024 samples ~= 46.4ms, or 512 samples ~= 23.2ms).
- In a SINGLE forward pass through audio, evaluates multiple lookahead scenarios:
  1. Lookahead = 0 ms (0 frames, pure causal right-edge)
  2. Lookahead = 23 ms (2 frames lookahead)
  3. Lookahead = 46 ms (4 frames lookahead)
  4. Lookahead = 93 ms (8 frames lookahead)
  5. Lookahead = 46 ms (Score-Guided Prior Filter)
  6. Lookahead = 0 ms (Score-Guided Prior Filter)
- Immediate Note-On Dispatch (Layer 1): Emits Note-On as soon as onset probability peaks,
  without waiting for note decay or minimum duration.
- Evaluates Precision, Recall, F1, algorithmic latency, and false positive rates.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

# Scipy compatibility
try:
    import scipy.signal
    if not hasattr(scipy.signal, "gaussian"):
        from scipy.signal.windows import gaussian
        scipy.signal.gaussian = gaussian
except ImportError:
    pass

try:
    import resampy
except ImportError:
    pass

try:
    import onnxruntime as ort
    from basic_pitch import build_icassp_2022_model_path, FilenameSuffix
except ImportError:
    print("Error: onnxruntime and basic-pitch are required.", file=sys.stderr)
    sys.exit(1)

from evaluate_basic_pitch import parse_midi_notes


class StreamingPipelineEvaluator:
    def __init__(
        self,
        session: ort.InferenceSession,
        hop_samples: int = 1024,
        configs: list = None,
        truth_shifted: list = None
    ):
        self.session = session
        self.input_name = session.get_inputs()[0].name
        self.buffer_size = 43844
        self.hop_samples = hop_samples
        self.sr = 22050
        self.configs = configs or []
        self.truth_shifted = truth_shifted or []

        # Ring buffer
        self.buffer = np.zeros(self.buffer_size, dtype=np.float32)
        self.total_samples_seen = 0

        # State per config
        self.history_per_config = [{} for _ in self.configs]
        self.detected_per_config = [[] for _ in self.configs]

    def process_chunk(self, audio_chunk: np.ndarray):
        n = len(audio_chunk)
        self.total_samples_seen += n

        # Slide ring buffer
        if n >= self.buffer_size:
            self.buffer = audio_chunk[-self.buffer_size:].astype(np.float32)
        else:
            self.buffer[:-n] = self.buffer[n:]
            self.buffer[-n:] = audio_chunk.astype(np.float32)

        # 1 Single ONNX inference for all configurations!
        inp = self.buffer.reshape(1, self.buffer_size, 1)
        outputs = self.session.run(None, {self.input_name: inp})
        onsets = outputs[1][0]  # (172, 88)
        frames = outputs[2][0]  # (172, 88)

        current_time_sec = self.total_samples_seen / float(self.sr)
        num_new_frames = max(1, self.hop_samples // 256)

        # Evaluate each configuration from the same outputs
        for cfg_idx, cfg in enumerate(self.configs):
            lookahead = cfg["lookahead_frames"]
            thresh = cfg["onset_thresh"]
            guide_filter = cfg.get("score_guide")

            eval_start_frame = max(0, 171 - lookahead - num_new_frames + 1)
            eval_end_frame = min(171, 171 - lookahead)

            hist = self.history_per_config[cfg_idx]
            events = self.detected_per_config[cfg_idx]

            for target_frame in range(eval_start_frame, eval_end_frame + 1):
                frame_offset_from_edge = 171 - target_frame
                target_time_sec = current_time_sec - (frame_offset_from_edge * 256.0 / float(self.sr))

                for pitch_idx in range(88):
                    pitch = pitch_idx + 21
                    onset_val = onsets[target_frame, pitch_idx]

                    if guide_filter is not None and pitch not in guide_filter:
                        continue

                    # Local peak condition
                    is_peak = True
                    if target_frame > 0 and onsets[target_frame - 1, pitch_idx] > onset_val:
                        is_peak = False
                    if target_frame < 171 and onsets[target_frame + 1, pitch_idx] > onset_val:
                        is_peak = False

                    last_time = hist.get(pitch, -1.0)
                    time_since_last = current_time_sec - last_time

                    if onset_val >= thresh and is_peak and time_since_last >= 0.08:
                        events.append({
                            "pitch": pitch,
                            "onset_act": float(onset_val),
                            "estimated_time": target_time_sec,
                            "reported_time": current_time_sec,
                            "algorithmic_latency_ms": (current_time_sec - target_time_sec) * 1000
                        })
                        hist[pitch] = current_time_sec


def run_streaming_benchmark():
    audio_path = "Fixtures/transcription/take1.wav"
    truth_path = "Fixtures/transcription/take1.truth.mid"

    audio_raw, orig_sr = sf.read(audio_path)
    if audio_raw.ndim > 1:
        audio_raw = np.mean(audio_raw, axis=1)

    if orig_sr != 22050:
        import resampy
        audio = resampy.resample(audio_raw, orig_sr, 22050)
    else:
        audio = audio_raw

    truth_raw = parse_midi_notes(truth_path)
    # Alignment: MIDI starts at 8.05s, audio starts at 0.05s
    offset = -(truth_raw[0][0] - 0.05)
    truth_shifted = [(t + offset, p, vel) for t, p, vel in truth_raw]
    guide_pitches = set(p for _, p, _ in truth_raw)

    model_path = build_icassp_2022_model_path(FilenameSuffix.onnx)
    session = ort.InferenceSession(model_path)

    configs = [
        {"name": "FIFO Streaming (0 ms Lookahead, causal)", "lookahead_frames": 0, "onset_thresh": 0.15, "score_guide": None},
        {"name": "FIFO Streaming (23 ms Lookahead / 2 frames)", "lookahead_frames": 2, "onset_thresh": 0.25, "score_guide": None},
        {"name": "FIFO Streaming (46 ms Lookahead / 4 frames)", "lookahead_frames": 4, "onset_thresh": 0.45, "score_guide": None},
        {"name": "FIFO Streaming (93 ms Lookahead / 8 frames)", "lookahead_frames": 8, "onset_thresh": 0.50, "score_guide": None},
        {"name": "FIFO Streaming (46 ms, Score-Guided Mask)", "lookahead_frames": 4, "onset_thresh": 0.45, "score_guide": guide_pitches},
        {"name": "FIFO Streaming (0 ms, Score-Guided Mask)", "lookahead_frames": 0, "onset_thresh": 0.15, "score_guide": guide_pitches},
    ]

    hop_samples = 1024  # 46.4 ms per chunk
    evaluator = StreamingPipelineEvaluator(
        session=session,
        hop_samples=hop_samples,
        configs=configs,
        truth_shifted=truth_shifted
    )

    print("\n" + "=" * 110)
    print("SPOTIFY BASIC PITCH: STREAMING FIFO RING-BUFFER + INSTANT NOTE-ON EVALUATION")
    print("=" * 110)
    print(f"Audio file: {audio_path} ({len(audio)/22050:.1f}s)")
    print(f"Hop size: {hop_samples} samples ({hop_samples/22.05:.1f} ms) | Buffer: 43,844 samples (1.988s)")
    print("Simulating live streaming chunk-by-chunk ingestion...")

    t0 = time.time()
    for i in range(0, len(audio), hop_samples):
        chunk = audio[i:i + hop_samples]
        if len(chunk) < hop_samples:
            chunk = np.pad(chunk, (0, hop_samples - len(chunk)), "constant")
        evaluator.process_chunk(chunk)
    total_time = time.time() - t0
    audio_dur = len(audio) / 22050.0
    rtf = total_time / audio_dur

    print(f"Completed streaming pipeline in {total_time:.2f}s (RTF: {rtf:.2f}x on CPU)\n")

    tolerance = 0.12
    summary = []

    print("─" * 110)
    print(f"{'Streaming Configuration':<46} │ {'Prec':>6} │ {'Recall':>6} │ {'F1':>6} │ {'Lat p50':>8} │ {'Lat p95':>8} │ {'False Alarms (Octave / Other)':>30}")
    print("─" * 110)

    for cfg_idx, cfg in enumerate(configs):
        det = evaluator.detected_per_config[cfg_idx]
        matched_truth = set()
        matched_events = []
        false_positives = []
        latencies = []

        for ev in det:
            s = ev["estimated_time"]
            rep = ev["reported_time"]
            p = ev["pitch"]
            match_idx = None
            best_diff = float("inf")
            for idx, (gt, gp, _) in enumerate(truth_shifted):
                if idx not in matched_truth and gp == p:
                    diff = abs(s - gt)
                    if diff <= tolerance and diff < best_diff:
                        best_diff = diff
                        match_idx = idx
            if match_idx is not None:
                matched_truth.add(match_idx)
                matched_events.append((ev, match_idx))
                # Latency: time from physical key strike (gt) to Note-On dispatch (rep)
                latencies.append(rep - truth_shifted[match_idx][0])
            else:
                false_positives.append(ev)

        tp = len(matched_truth)
        fp = len(false_positives)
        fn = len(truth_shifted) - tp

        p_score = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        r_score = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * p_score * r_score / (p_score + r_score) if (p_score + r_score) > 0 else 0.0

        lat_ms = [max(0, l * 1000) for l in latencies]
        lat_ms.sort()
        p50 = lat_ms[int(len(lat_ms) * 0.5)] if lat_ms else 0.0
        p95 = lat_ms[int(len(lat_ms) * 0.95)] if lat_ms else 0.0

        octave_fps = sum(1 for ev in false_positives if any(abs(ev["estimated_time"] - gt) <= 0.4 and (ev["pitch"] == gp + 12 or ev["pitch"] == gp + 24) for gt, gp, _ in truth_shifted))
        other_fps = fp - octave_fps
        fp_label = f"{fp:2d} ({octave_fps:2d} oct / {other_fps:2d} oth)"

        print(f"{cfg['name']:<46} │ {p_score:6.3f} │ {r_score:6.3f} │ {f1:6.3f} │ {p50:6.0f} ms │ {p95:6.0f} ms │ {fp_label:>30}")

        summary.append({
            "name": cfg["name"],
            "lookahead_frames": cfg["lookahead_frames"],
            "lookahead_ms": cfg["lookahead_frames"] * 256.0 / 22.05,
            "hop_ms": hop_samples / 22.05,
            "onset_thresh": cfg["onset_thresh"],
            "score_guided": cfg["score_guide"] is not None,
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "octave_fp": octave_fps,
            "other_fp": other_fps,
            "precision": p_score,
            "recall": r_score,
            "f1": f1,
            "latency_p50_ms": p50,
            "latency_p95_ms": p95,
        })

    print("=" * 110 + "\n")

    # Save to JSON
    out_file = "docs/streaming_basic_pitch_eval.json"
    with open(out_file, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"Results saved to {out_file}")


if __name__ == "__main__":
    run_streaming_benchmark()
