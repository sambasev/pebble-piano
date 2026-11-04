# Meta Hackathon: Recorded Video Demo Script & Storyboard
**App:** Pebble Piano (PianoPad) · **Track:** Multimodal AI & Meta Model API  
**Duration:** 3:00 Minutes · **Format:** Screen Recording + Voiceover & Camera PiP

---

## Storyboard Overview

| Timestamp | Section | Visual Focus | Key Narrative |
|---|---|---|---|
| **0:00–0:35** | **The Hook & Problem** | Pebble Piano interactive app + Physical Beyer book | The grand staff OMR challenge for piano beginners |
| **0:35–1:15** | **From Book Page to Lines** | Books view: open a PDF, staves boxed automatically, pick a piece | Pebble Piano finds each system by its staff lines; Muse Wonder reads them |
| **1:15–1:55** | **The Model Shootout** | Benchmark charts & tables (LEGATO vs Spark vs Wonder) | Why Muse Wonder's high reasoning dominates polyphony |
| **1:55–2:30** | **The Hybrid Breakthrough** | Visual overlay (`ai_probe3 --draw`) with green noteheads | Pairing Wonder's rhythm with CV notehead geometry: 94.8% on 1895 scans, 100% on modern scores |
| **2:30–3:00** | **Turnkey Scale & In-App Play** | Automated LilyPond compiler + In-App Wait Mode | 170+ exercises generated; live interactive piano guide |

---

## Detailed Script & Directing Notes

### Scene 1: The Hook & The Problem (0:00 – 0:35)

- **On Screen**:
  - Start with Pebble Piano (`PianoPad.app`) open on macOS.
  - The presenter plays a short phrase on a connected MIDI keyboard or computer keyboard. The keys light up purple, notes turn green, and the wait guide advances.
  - Cut to a physical copy or PDF of Ferdinand Beyer's *Op. 101* (1895 Peters edition).
- **Voiceover**:
  > "Learning the piano is magical when software listens and guides you in real time.
  > But millions of students learn from physical books—like Ferdinand Beyer's classic Op. 101.
  > Traditional Optical Music Recognition falls apart on piano grand staves: dual treble clefs, independent voice timing, and vintage paper textures cause missing notes and broken measures.
  > For this hackathon, we set out to solve the piano OMR challenge using Meta's multimodal model ecosystem—turning raw sheet music into interactive, playable lessons."

---

### Scene 2: From Book Page to Lines of Music (0:35 – 1:15)

- **On Screen**:
  - In Pebble Piano, open **Books** and click **Open a book (PDF)…**. Choose the Beyer *Op. 101* PDF and go to a page with non-uniform margins and historical print noise.
  - Numbered boxes appear around each grand-staff system on the page, found automatically.
  - Click the first line of the piece, then Shift-click its last line. Drag one box edge to show it can be adjusted by hand.
  - Start the reading: "Reading the piece…" while Muse Wonder reads each line.
- **Voiceover**:
  > "First, open the book. Pebble Piano finds every system on the page by its staff lines, then pairs each treble staff with the bass staff below it. This is plain geometry running on the Mac, with no AI and no upload, and it copes with uneven margins and old print.
  > Pick the piece: click its first line, then Shift-click its last. If a box misses a note, drag its edge.
  > Each line is then cut out and sent to Meta's Muse Wonder to read. In our benchmark, one line at a time read far more accurately than a whole page."

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
  - Back in **Books**, step through the bars it flagged with **Next to check**, then click **Save and practise**.
  - The piece opens in Practice, ready to play.
  - The presenter plays the piece: notes light up green, the wait playhead tracks every chord, and the auto-grader awards 3 stars upon completion.
- **Voiceover**:
  > "To ensure our evaluation is rigorous, our automated LilyPond pipeline scales this benchmark across 170+ progressive two-hand exercises in the cloud.
  > And best of all, the output isn't just data—it flows directly into Pebble Piano.
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
  - `Books/F_Beyer-Op101.pdf` (for the Books scene; read the piece once beforehand so a saved reading is ready if the live one is slow)
- [ ] **Software Ready**:
  - Pebble Piano running in Xcode with Sound on and Guide toggled on.
  - Modal dashboard or terminal with `uv run` commands ready.
