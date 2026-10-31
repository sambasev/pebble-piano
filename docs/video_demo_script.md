# Meta Hackathon: Recorded Video Demo Script & Storyboard
**App:** PerfectPiano (PianoPad) · **Track:** Multimodal AI & Meta Model API  
**Duration:** 3:00 Minutes · **Format:** Screen Recording + Voiceover & Camera PiP

---

## Storyboard Overview

| Timestamp | Section | Visual Focus | Key Narrative |
|---|---|---|---|
| **0:00–0:35** | **The Hook & Problem** | PerfectPiano interactive app + Physical Beyer book | The grand staff OMR challenge for piano beginners |
| **0:35–1:15** | **SAM 3.1 Layout Understanding** | Raw scan + Live SAM 3.1 zero-shot segmentation | Extracting systems and barlines in < 2 seconds |
| **1:15–1:55** | **The Model Shootout** | Benchmark charts & tables (LEGATO vs Spark vs Wonder) | Why Muse Wonder's high reasoning dominates polyphony |
| **1:55–2:30** | **The Hybrid Breakthrough** | Visual overlay (`ai_probe3 --draw`) with green noteheads | Pairing Wonder's rhythm with CV notehead geometry = 99% |
| **2:30–3:00** | **Turnkey Scale & In-App Play** | Automated LilyPond compiler + In-App Wait Mode | 170+ exercises generated; live interactive piano guide |

---

## Detailed Script & Directing Notes

### Scene 1: The Hook & The Problem (0:00 – 0:35)

- **On Screen**:
  - Start with PerfectPiano (`PianoPad.app`) open on macOS.
  - The presenter plays a short phrase on a connected MIDI keyboard or computer keyboard. The keys light up purple, notes turn green, and the wait guide advances.
  - Cut to a physical copy or PDF of Ferdinand Beyer's *Op. 101* (1895 Peters edition).
- **Voiceover**:
  > "Learning the piano is magical when software listens and guides you in real time.
  > But millions of students learn from physical books—like Ferdinand Beyer's classic Op. 101.
  > Traditional Optical Music Recognition falls apart on piano grand staves: dual treble clefs, independent voice timing, and vintage paper textures cause missing notes and broken measures.
  > For this hackathon, we set out to solve the piano OMR challenge using Meta's multimodal model ecosystem—turning raw sheet music into interactive, playable lessons with 99% accuracy."

---

### Scene 2: Document Layout Understanding with SAM 3.1 (0:35 – 1:15)

- **On Screen**:
  - Show the 1895 Beyer scan (`op101-p24.png` or `op101-p27.png`) with non-uniform margins and historical print noise.
  - Terminal or UI showing SAM 3.1 call via Meta Model API:
    `client.segment(image: pageData, prompt: "grand staff")`
  - Bounding boxes appear dynamically around each system, accompanied by SAM's segmentation output tokens.
  - Transition to cropped systems ready for notation transcription.
- **Voiceover**:
  > "First: page layout understanding.
  > Instead of fragile classical edge-detection, we use Meta's Segment Anything Model—SAM 3.1—hosted on the Meta Model API.
  > With zero fine-tuning, SAM reliably segments grand staves, music systems, and barlines in under 2 seconds.
  > It handles historical ink bleed, page rotation, and non-standard spacing, cleanly isolating each musical system for reading."

---

### Scene 3: The Model Shootout (1:15 – 1:55)

- **On Screen**:
  - Display the benchmark chart: `omr_model_shootout.png` (from `.build/eval_charts/`).
  - Side-by-side comparison of transcribed measures against the ground truth answer key (`truth/pieces.json`).
  - Show LEGATO repetition failure on cropped systems, Muse Spark's 70%, and Muse Wonder's 88%.
- **Voiceover**:
  > "Next, we benchmarked notation recognition across three architectures:
  > First, LEGATO—an open-weight model fine-tuned on Llama 3.2 Vision 11B deployed on a Modal L40S GPU. While capable on full modern pages, it struggles with domain generalization on historical cropped systems, getting trapped in autoregressive repetition loops.
  > Second, Muse Spark 1.3: fast and capable on clean scores, achieving 70% note accuracy, but dropping on vintage scans.
  > Finally, Meta's flagship Muse Wonder 1.0: its deep reasoning capabilities excel at polyphonic texture, dual clefs, and complex note durations, achieving 88% note accuracy and 71% exact bar matches out of the box."

---

### Scene 4: The Hybrid Engineering Breakthrough (1:55 – 2:30)

- **On Screen**:
  - Display the visual annotated overlay (`.build/ai-probe3/scan-no12.png` or `modern-no12.png`).
  - Zoom into a measure: show blue vertical lines on barlines, orange circles on raw detections, and bright green circles with pitch labels snapping onto staff lines.
  - Flash the ablation chart (`hybrid_ablation_breakthrough.png`) showing the jump from 88% to 100%.
- **Voiceover**:
  > "Even state-of-the-art vision models can occasionally shift a notehead by a single line or space—turning an E4 into a D4.
  > To solve this 'last-mile' problem, we engineered a hybrid pipeline:
  > Muse Wonder provides the high-level semantic reasoning—identifying metre, barlines, note durations, and voicing.
  > Then, our deterministic computer vision algorithm projects notehead centroids onto deskewed staff lines to lock in pitch.
  > The result? Note accuracy leaps to 95% on 1895 historical scans and a flawless 100% on modern scores, with zero silent errors."

---

### Scene 5: Scale & In-App Interactive Play (2:30 – 3:00)

- **On Screen**:
  - Quick cut to `scripts/expand_benchmark.py`: compiling LilyPond sources on Modal to scale the benchmark across 170+ two-hand exercises.
  - Seamless import: click `Open MIDI file…` in PerfectPiano.
  - The freshly transcribed piece is rendered instantly on the screen as engraved notation.
  - The presenter plays the piece: notes light up green, the wait playhead tracks every chord, and the auto-grader awards 3 stars upon completion.
- **Voiceover**:
  > "To ensure our evaluation is rigorous, our automated LilyPond pipeline scales this benchmark across 170+ progressive two-hand exercises in the cloud.
  > And best of all, the output isn't just data—it flows directly into PerfectPiano.
  > Students can immediately practice the piece with interactive key lights, wait-mode pacing, and real-time grading.
  > With Meta's models, we've bridged the gap from paper to performance."

---

## Screen Recording Checklist

- [ ] **Assets**:
  - `op101-p24.png` and `op101-p27.png` (historical scans)
  - `Fixtures/beyer/crops/no12.png` and `no13.png`
  - `.build/eval_charts/omr_model_shootout.png`
  - `.build/eval_charts/hybrid_ablation_breakthrough.png`
  - `.build/eval_charts/omr_pareto_frontier.png`
  - `.build/ai-probe3/scan-no12.png` and `modern-no12.png` (with green circle overlays)
  - `Fixtures/beyer/midi/no12-wonder.mid` (ready to drag into PerfectPiano)
- [ ] **Software Ready**:
  - PerfectPiano running in Xcode with Sound on and Guide toggled on.
  - Modal dashboard or terminal with `uv run` commands ready.
