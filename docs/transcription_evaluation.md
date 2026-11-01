# Audio-to-MIDI Transcription Evaluation Report

This report benchmarks real-time audio-to-MIDI piano transcription methods in **PerfectPiano** alongside external polyphonic pitch detection models (including **Spotify's Basic Pitch** neural network).

---

## 1. Executive Summary & Benchmark Results

### A. Full Corpus Benchmark (9 Synthetic Acoustic Test Cases + Real Piano Fixtures)

Evaluated across dry studio, reverberant room, and ambient noise environments with polyphonic triads, neighbor mistakes, and wide register extremes (A0–C8):

| Model / Method | Precision | Recall | F1 Score | Latency ($p_{50}$) | Latency ($p_{95}$) | Clean Acceptance | RTF (Compute) | Native / Realtime |
|---|---|---|---|---|---|---|---|---|
| **Score-Informed NMF** (Production) | **0.958** | **0.863** | **0.908** | 89 ms | 89 ms | **85.5%** | 0.18x | Yes (8ms streaming) |
| **Free-Play NMF (Unguided)** | 0.985 | 0.838 | 0.905 | 89 ms | 89 ms | 82.9% | 0.14x | Yes (8ms streaming) |
| **NMF (Fast 30ms Delay)** | 0.863 | 0.863 | 0.863 | **65 ms** | **65 ms** | 85.5% | 0.14x | Yes (8ms streaming) |
| **NMF (5 Iterations Light)** | 0.958 | 0.863 | 0.908 | 89 ms | 89 ms | 85.5% | **0.09x** | Yes (8ms streaming) |
| **Spectral Peak Baseline** | 0.450 | 0.725 | 0.555 | 88 ms | 94 ms | 76.3% | 0.00x | Yes (FFT peak pick) |

> **RTF (Real-Time Factor)**: Compute time ÷ audio duration. $0.09\text{x}$ means processing 1 second of audio takes only 90 ms on CPU (>10x real-time headroom).

---

### B. Real Acoustic Piano Take (`take1.wav` + Ground Truth MIDI)

Direct side-by-side comparison between PerfectPiano's streaming CQT-NMF engine and **Spotify's Basic Pitch** (ICASSP 2022 CNN, ONNX runtime):

| Model / Configuration | Precision | Recall | F1 Score | Latency ($p_{50}$) | Latency ($p_{95}$) | RTF | False Alarms |
|---|---|---|---|---|---|---|---|
| **Score-Informed NMF** (PerfectPiano) | **1.000** | **1.000** | **1.000** | 59 ms | 92 ms | 0.11x | **0** |
| **Spotify Basic Pitch (Score-Guided Filter)** | **1.000** | **1.000** | **1.000** | 86 ms | 99 ms | 0.03x | **0** |
| **Spotify Basic Pitch (Tuned 0.6/0.4)** | 0.842 | 1.000 | 0.914 | 86 ms | 99 ms | 0.04x | 3 (2 octaves) |
| **Spotify Basic Pitch (Default 0.5/0.3)** | 0.696 | 1.000 | 0.821 | 86 ms | 99 ms | 0.06x | 7 (5 octaves) |
| **Spectral Peak Baseline** | 0.390 | 1.000 | 0.561 | 93 ms | 97 ms | 0.00x | 25 (overtone clutter) |

---

## 2. Spotify Basic Pitch: How It Works & How to Evaluate It

### What is Spotify Basic Pitch?
Spotify's Basic Pitch (Bittner et al., ICASSP 2022) is an open-source lightweight polyphonic pitch prediction model. It uses:
1. **Harmonic Stack Spectrogram**: A Constant-Q / FFT transform evaluated across multiple harmonic multiples ($f_0, 2f_0, 3f_0, \dots$).
2. **Convolutional Neural Network**: Predicts note activations, onsets, and pitch bends across 88 piano keys.
3. **Melodia Trick Post-Processing**: Traces temporal continuity to form discrete note events.

### Why Evaluate External Models?
Evaluating external neural models answers three fundamental questions for PerfectPiano:
1. **Accuracy Ceiling**: What is the raw polyphonic detection accuracy of an unconstrained deep neural net on acoustic piano?
2. **Acoustic Physics & Overtone Leakage**: Does a neural model suffer from the same harmonic overtone false positives as signal processing methods?
3. **Latency & Embedded Suitability**: Can a neural model run on-device inside a low-latency interactive piano tutor on iOS/macOS?

---

## 3. Acoustic Insights: Why Basic Pitch Triggers Ghost Octaves

On real acoustic piano audio (`take1.wav`), unguided Basic Pitch achieved **100% recall (16/16)** but suffered from a **69.6% precision rate due to 7 false positive triggers**.

Acoustic breakdown of Basic Pitch false alarms:
- **71.4% (5 notes)** were **Octave Harmonics (+12 or +24 semitones)**:
  - Striking $C_4$ (pitch 60) triggered a phantom $C_5$ (pitch 72).
  - Striking $F_4$ (pitch 65) triggered a phantom $F_5$ (pitch 77).
  - Striking $D_3$ (pitch 50) triggered a phantom $D_4$ (pitch 62).
  - Striking $C_3$ (pitch 48) triggered a phantom $C_4$ (pitch 60).
- **28.6% (2 notes)** were **String Resonance Re-triggers**:
  - Sympathetic vibration during long key decay triggered re-attacks.

### The Score-Informed Solution
In an interactive score tracker like PerfectPiano:
- The app knows what notes the student is supposed to play (the guide).
- **Score-Informed NMF** applies a penalty matrix favoring expected pitches and penalizing octave relatives ($+12, +19, +24$ semitones).
- When the same score-expectation filter was applied to Basic Pitch's predictions, precision rose from **0.696 to 1.000**, with **zero false alarms**.

---

## 4. Latency & Architecture Comparison

| Dimension | PerfectPiano (Streaming NMF) | Spotify Basic Pitch (CNN) |
|---|---|---|
| **Pipeline Mode** | **Streaming Causal** (8ms hop increments) | **Chunked / Framing** (30s batch or sliding windows) |
| **Algorithmic Latency** | **65 ms – 89 ms** ($p_{50}$) | **150 ms – 250 ms** (minimum chunk lookahead) |
| **Dependencies** | **0 external dependencies** (Pure Swift + Accelerate) | Python, ONNX Runtime / TensorFlow, NumPy, SciPy |
| **App Size Impact** | **< 100 KB binary size** | **20 MB – 150 MB** weights + runtime |
| **Score Conditioning** | **Native dynamic priors** (KL divergence penalties) | Unconstrained only (requires custom output masking) |

---

## 5. How to Run the Evaluations

### Running the Swift Benchmark Suite:
```bash
# Evaluate all models across dry, room, and noisy environments:
swift run grade eval

# Evaluate specifically on user fixtures:
swift run grade eval --fixtures Fixtures/transcription

# Detailed register breakdown (Bass, Mid, Treble):
swift run grade eval --detail

# Export JSON and Markdown reports:
swift run grade eval --markdown docs/transcription_evaluation.md --json docs/transcription_evaluation.json
```

### Running Spotify Basic Pitch Evaluation:
We provide the standalone evaluation tool `scripts/evaluate_basic_pitch.py`:
```bash
# Evaluate Spotify Basic Pitch (ONNX) on real piano takes:
uv run --with "basic-pitch[onnx],setuptools<70,mido,scipy" \
  scripts/evaluate_basic_pitch.py \
  --fixtures Fixtures/transcription \
  --json docs/basic_pitch_eval.json \
  --markdown docs/basic_pitch_eval.md
```
The script automatically:
1. Runs ONNX neural inference on `.wav` files.
2. Auto-aligns time offsets between audio and MIDI truth via onset cross-correlation.
3. Evaluates Precision, Recall, F1 against ground truth ($\pm 120\text{ ms}$).
4. Diagnoses false-positive triggers by harmonic interval (octaves, fifths/twelfths).
5. Compares raw unguided predictions vs score-informed masked predictions.
