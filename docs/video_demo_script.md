# Meta Hackathon: Recorded Video Demo Script & Storyboard
**App:** Pebble Piano · **Track:** Multimodal AI & Meta Model API  
**Duration:** 3:00 Minutes · **Format:** Screen Recording + Voiceover & Camera PiP

All numbers below come from the OMR evaluation report (`docs/omr_evaluation.md`,
`docs/omr_evaluation.json`). If the report changes, update this script to match.

---

## Storyboard Overview

| Timestamp | Section | Visual Focus | Key Narrative |
|---|---|---|---|
| **0:00–0:35** | **The Hook & Problem** | Pebble Piano interactive app + Physical Beyer book | The grand staff OMR challenge for piano beginners |
| **0:35–1:15** | **One Line at a Time** | Raw scan split into single-line crops | Line crops beat full pages: Spark +25%, LEGATO decodes in 5.8s |
| **1:15–1:55** | **The Model Shootout** | Benchmark chart & table (LEGATO vs Spark vs Wonder) | LEGATO wins on clean scores but fails on the 1895 scan; Wonder works on both |
| **1:55–2:30** | **The Hybrid Breakthrough** | Visual overlay (`ai_probe3 --draw`) with green noteheads | Wonder's rhythm + CV notehead geometry = 94.8% on 1895 scans, 100% on modern |
| **2:30–3:00** | **Turnkey Scale & In-App Play** | Automated LilyPond compiler + In-App Wait Mode | 170+ exercises generated; live interactive piano guide |

---

## Detailed Script & Directing Notes

### Scene 1: The Hook & The Problem (0:00 – 0:35)

- **On Screen**:
  - Start with Pebble Piano open on macOS.
  - The presenter plays a short phrase on a connected MIDI keyboard or computer keyboard. The keys light up purple, notes turn green, and the wait guide advances.
  - Cut to a physical copy or PDF of Ferdinand Beyer's *Op. 101* (1895 Peters edition).
- **Voiceover**:
  > "Learning the piano is magical when software listens and guides you in real time.
  > But millions of students learn from physical books—like Ferdinand Beyer's classic Op. 101.
  > Traditional Optical Music Recognition falls apart on piano grand staves: two staves, independent voice timing, and vintage paper textures cause missing notes and broken measures.
  > For this hackathon, we set out to solve the piano OMR challenge using Meta's multimodal models—turning a 130-year-old book into interactive, playable lessons, with 95% of notes right on the original scans and 100% on modern scores."

---

### Scene 2: One Line at a Time (0:35 – 1:15)

- **On Screen**:
  - Show the 1895 Beyer scan (`Fixtures/beyer/op101-p24.png` or `op101-p27.png`) with non-uniform margins and historical print noise.
  - Show the page split into single-line crops (`Fixtures/beyer/crops/no12.png`, `no13.png`).
  - Optionally, a quick shot of the SAM 3.1 probe (`scripts/ai_probe2.py`) finding systems on the page.
- **Voiceover**:
  > "First: page layout.
  > A full page of piano music is too much to read in one go, so we cut the page into single lines of music before any model reads it.
  > We tested this with Meta's Segment Anything Model, SAM 3.1: feeding one-line crops instead of the full page lifted Muse Spark's accuracy by 25%, and let the open-weight LEGATO model finish a line in under 6 seconds, stopping cleanly at the final barline.
  > In the app, Pebble Piano finds the lines itself, so every line arrives clean and ready to read."

> **Accuracy note:** in the shipping app, lines are found by Pebble Piano's own code
> (`Sources/PianoAI/SystemFinder.swift`), not SAM. SAM 3.1 was used in the probe scripts and the
> report's crop experiment. Don't show SAM as part of the app's import.

---

### Scene 3: The Model Shootout (1:15 – 1:55)

- **On Screen**:
  - Display the benchmark chart: `docs/charts/omr_model_shootout.png`.
  - Show the results table from `docs/omr_evaluation.md`, compared against the answer key (`Fixtures/beyer/truth/`).
  - Show LEGATO's repetition loop on the 1895 crop, its perfect modern page, Muse Spark's 47% / 70%, and Muse Wonder's 88%.
- **Voiceover**:
  > "Next, we benchmarked three models on the same Beyer pieces.
  > First, LEGATO—an open-weight model built on Llama 3.2 Vision 11B, running on a Modal L40S GPU. On a clean modern score it's superb: a full page, 16 out of 16 bars exactly right, in 9 seconds. But on the 1895 scan it fell into a repetition loop—the same chord, 87 bars in a row—and got nothing right.
  > Second, Muse Spark 1.3: 70% of notes right on modern scores, dropping to 47% on the vintage scan.
  > Finally, Meta's Muse Wonder 1.0: 88% of notes right on both the vintage scan and the modern scores, and the rhythm right every single time—metre, barlines, note lengths and which hand plays what. It's slower, about a minute or two per line, but it's the only model that held up on a real old book."

---

### Scene 4: The Hybrid Engineering Breakthrough (1:55 – 2:30)

- **On Screen**:
  - Display the visual annotated overlay (`.build/ai-probe3/scan-no12.png` or `modern-no12.png`, from `scripts/ai_probe3.py --draw`).
  - Zoom into a measure: show blue vertical lines on barlines, orange circles on raw detections, and bright green circles with pitch labels snapping onto staff lines.
  - Flash the ablation chart (`docs/charts/hybrid_ablation_breakthrough.png`) showing the jump from 88% to 94.8% (1895 scan) and 100% (modern).
  - Optionally, the Pareto chart (`docs/charts/omr_pareto_frontier.png`): LEGATO fastest on clean scores, Hybrid most robust on vintage scans.
- **Voiceover**:
  > "Wonder's one weakness is pitch: it sometimes shifts a notehead by a single line or space—turning an E4 into a D4.
  > To solve this 'last-mile' problem, we engineered a hybrid pipeline:
  > Muse Wonder provides the musical structure—metre, barlines, note durations and voicing.
  > Then our own computer vision finds the staff lines and each notehead's centre, and snaps every note to the right pitch.
  > The result? Note accuracy jumps from 88% to 94.8% on the 1895 scans, and to 100%—155 out of 155 notes—on modern scores. And the app flags any bar it isn't sure of, so there are no silent errors."

---

### Scene 5: Scale & In-App Interactive Play (2:30 – 3:00)

- **On Screen**:
  - Quick cut to `scripts/expand_benchmark.py`: compiling LilyPond sources on Modal to scale the benchmark across 170+ two-hand exercises.
  - Seamless import: click `Open MIDI file…` in Pebble Piano.
  - The freshly transcribed piece is rendered instantly on the screen as engraved notation.
  - The presenter plays the piece: notes light up green, the wait playhead tracks every chord, and the auto-grader awards 3 stars upon completion.
- **Voiceover**:
  > "To keep the evaluation growing, our automated LilyPond pipeline can generate 170+ progressive two-hand exercises in the cloud.
  > And best of all, the output isn't just data—it flows directly into Pebble Piano.
  > Students can immediately practice the piece with interactive key lights, wait-mode pacing, and real-time grading.
  > With Meta's models, we've bridged the gap from paper to performance."

---

## Claims to keep accurate

- **Sample sizes are small.** Wonder and Spark: about 28 bars per condition; the hybrid rows: 56 bars; LEGATO's modern results: one piece (8 bars as a line crop, 16 as a full page). Say "on our Beyer benchmark", not "in general".
- **LEGATO and Wonder weren't tested on identical inputs.** LEGATO's 100% is on a full modern page; Wonder was only tested on one-line crops. Don't call it a head-to-head on the same page.
- **Use the report's numbers:** 94.8% (1895 scans) and 100% (modern) for the hybrid, not "99%".

---

## Screen Recording Checklist

- [ ] **Assets**:
  - `Fixtures/beyer/op101-p24.png` and `op101-p27.png` (historical scans)
  - `Fixtures/beyer/crops/no12.png` and `no13.png`
  - `docs/charts/omr_model_shootout.png`
  - `docs/charts/hybrid_ablation_breakthrough.png`
  - `docs/charts/omr_pareto_frontier.png`
  - `.build/ai-probe3/scan-no12.png` and `modern-no12.png` (with green circle overlays; run `scripts/ai_probe3.py --draw`)
  - `Fixtures/beyer/midi/beyer-no12-wonder.mid` (ready to drag into Pebble Piano)
- [ ] **Software Ready**:
  - Pebble Piano running in Xcode with Sound on and Guide toggled on.
  - Modal dashboard or terminal with `uv run` commands ready.
