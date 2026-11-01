# Streaming Spotify Basic Pitch: FIFO Ring Buffer & Low-Latency Evaluation

This report documents the experimental evaluation of streaming **Spotify Basic Pitch** using a **FIFO Ring Buffer (Layer 2)** and **Immediate Note-On Dispatch (Layer 1)** on acoustic piano audio (`take1.wav` + `take1.truth.mid`).

---

## 1. Streaming Architecture Tested

```
Audio Input Stream (48 kHz -> resampled to 22,050 Hz)
       │
       ▼
[43,844-sample FIFO Ring Buffer (~1.988 s past audio)]
       │
       ▼  (Inference triggered every hop of 1024 samples = 46.4 ms)
[ONNX Neural Network Inference (60.4 ms compute)]
       │
       ▼
Output Tensor: Onset Activations (172 frames x 88 keys)
       │
       ▼
Evaluate Target Window: (171 - Lookahead Frames)
       │
       ├── Lookahead = 0 ms  (Frame 171: Pure Causal Right-Edge)
       ├── Lookahead = 23 ms (Frame 169: 2 Frames Lookahead)
       ├── Lookahead = 46 ms (Frame 167: 4 Frames Lookahead)
       └── Lookahead = 93 ms (Frame 163: 8 Frames Lookahead)
       │
       ▼
Immediate Note-On Dispatch:
  Trigger Note-On immediately when onset activation crosses threshold & local peak,
  completely bypassing offline decay tracking (min_note_len = 128ms).
```

---

## 2. Quantitative Results & Tradeoff Matrix

Evaluated on `take1.wav` (32.1 seconds of acoustic piano):

| Streaming Configuration | Lookahead | Precision | Recall | F1 Score | Latency ($p_{50}$) | Latency ($p_{95}$) | False Alarms | Practical Usability |
|---|---|---|---|---|---|---|---|---|
| **0 ms Lookahead (Pure Causal Edge)** | 0 ms | 0.016 | **1.000** | 0.032 | **40 ms** | **60 ms** | 961 (36 oct / 925 oth) | ❌ Unusable (chatter storm) |
| **0 ms Lookahead (Score-Guided Mask)** | 0 ms | 0.084 | **1.000** | 0.155 | **40 ms** | **60 ms** | 175 (25 oct / 150 oth) | ❌ Unusable (decay repeats) |
| **23 ms Lookahead (2 frames)** | 23 ms | 0.714 | 0.938 | 0.811 | **68 ms** | 96 ms | 6 (4 octaves / 2 oth) | ⚠️ Acceptable (with score filter) |
| **46 ms Lookahead (4 frames)** | 46 ms | **0.833** | 0.938 | **0.882** | 87 ms | 122 ms | **3 (0 octaves / 3 oth)** |  **Optimal Neural Sweet Spot** |
| **46 ms (Score-Guided Mask)** | 46 ms | **0.833** | 0.938 | **0.882** | 87 ms | 122 ms | **3 (0 octaves / 3 oth)** |  **Optimal Neural Sweet Spot** |
| **93 ms Lookahead (8 frames)** | 93 ms | 0.242 | **1.000** | 0.390 | 147 ms | 212 ms | 50 (decay repeats) | ❌ High latency & chatter |
| **Offline Full Batch (Baseline)** | ~2000 ms | 0.842 | **1.000** | 0.914 | 86 ms | 99 ms | 3 (2 octaves / 1 oth) | ℹ️ Offline reference only |
| **PerfectPiano Score-Informed NMF** | **0 ms** | **1.000** | **1.000** | **1.000** | **59 ms** | **92 ms** | **0 (vetoed)** |  **Production Real-Time Engine** |

---

## 3. Key Findings & Insights

### 1. The Zero-Lookahead Receptive Field Cliff
- At **0 ms lookahead** (evaluating frame 171 at the raw right edge), the model’s onset activation for a struck key drops from **0.75+ down to 0.136**.
- The non-causal convolutional layers require post-attack audio to distinguish a true note strike from a transient click.
- Lowering the threshold to 0.15 catches the notes (Recall = 100%), but triggers **961 false alarms** across 32 seconds (chatter storm, Precision = 1.6%).
- **Conclusion**: A non-causal model cannot be run at pure zero-lookahead simply by lowering the threshold.

### 2. The 46 ms "Sweet Spot"
- Providing just **4 frames ($\approx 46\text{ ms}$) of lookahead** restores the onset activation to **0.662–0.774**.
- F1 score reaches **0.882** (Recall 93.8%, Precision 83.3%), with only 3 false alarms.
- The end-to-end algorithmic latency ($p_{50}$) is **87 ms**, which is fast enough for interactive piano practice.

### 3. CPU / RTF Bottleneck
- On Apple Silicon CPU, a single ONNX inference takes **60.4 ms**.
- Hopping by 46.4 ms (1024 samples) yields an RTF of **1.34x** (43 seconds compute for 32 seconds audio), which exceeds the real-time budget on a single CPU thread.
- To deploy this streaming architecture in production on iOS/macOS, the model must be converted to **CoreML float16 / INT8** to run on the Apple Neural Engine (< 5 ms inference).
