# Spotify Basic Pitch vs. Score-Informed Transcription Benchmark

Evaluated on ground-truth acoustic piano audio (`take1.wav` + `.truth.mid`).

## Performance Comparison

| Model / Configuration | Precision | Recall | F1 Score | Latency (p50) | Latency (p95) | RTF (Compute) |
|---|---|---|---|---|---|---|
| **Spotify Basic Pitch (Default 0.5/0.3)** | 0.696 | 1.000 | **0.821** | 86 ms | 99 ms | 0.06x |
| **Spotify Basic Pitch (Tuned 0.6/0.4)** | 0.842 | 1.000 | **0.914** | 86 ms | 99 ms | 0.04x |
| **Spotify Basic Pitch (Score-Guided)** | 1.000 | 1.000 | **1.000** | 86 ms | 99 ms | 0.03x |

## Key Acoustic Insights

1. **Harmonic Overtone Ghosting**: Uninformed polyphonic neural estimators like Basic Pitch suffer from harmonic octave triggers (+12 semitones above the fundamental) when acoustic piano strings are struck forcefully.
2. **Score-Informed Advantage**: When the guide score is applied as an expectation filter, Precision jumps from **0.696 to 1.000**, and F1 from **0.821 to 1.000**.
3. **Latency & Streaming**: Basic Pitch is designed for framing/chunked inference (~150–250ms streaming latency), whereas PerfectPiano's NMF runs with 8ms hops (65–89ms latency).
