# Audio-to-MIDI Transcription Evaluation Report

Evaluated on 9 test cases across acoustic conditions.

## Overall Model Comparison

| Model / Method | Precision | Recall | F1 Score | Latency (p50) | Latency (p95) | Clean Acceptance | RTF (Compute) |
|---|---|---|---|---|---|---|---|
| **Score-Informed NMF** | 0.958 | 0.863 | **0.908** | 89 ms | 89 ms | 85.5% | 0.18x |
| **Free-Play NMF (Unguided)** | 0.985 | 0.838 | **0.905** | 89 ms | 89 ms | 82.9% | 0.14x |
| **Spectral Peak (Baseline)** | 0.450 | 0.725 | **0.555** | 88 ms | 94 ms | 76.3% | 0.00x |
| **NMF (Fast 30ms Delay)** | 0.863 | 0.863 | **0.863** | 65 ms | 65 ms | 85.5% | 0.14x |
| **NMF (5 Iterations)** | 0.958 | 0.863 | **0.908** | 89 ms | 89 ms | 85.5% | 0.09x |

> **RTF (Real-Time Factor)**: Audio processing time ÷ duration. Values < 0.1x indicate fast real-time CPU headroom.
