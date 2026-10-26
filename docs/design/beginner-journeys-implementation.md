# Beginner Journeys: Implementation Plan

Oct 25, 2026 · Sam

This is how to build [beginner-journeys.md](beginner-journeys.md) on top of the current code. Each milestone is one branch and one merge. Each one can be shipped on its own and tested in TestFlight.

## Architecture in one picture

```
PianoLessons (new target, Foundation + PianoGraderCore, unit-tested)
  LessonUnit / LessonPage / Block  the JSON model and loader (`LoadedUnit`)
  LessonEngine                   pure state machine: block → attempts → hint → escalate → done
  Stars, RemediationPlanner      pure functions over GradeReport
  Persona                        Alex and Kriti settings files

PianoPadState (existing)
  LearnerSettings  + persona, goalSong, inputSource
  LearnerHistory   + lessons.json (page progress), sessions.json (session log)
  PieceID          + .lesson(unit, page, block)

PianoPad (app)
  LessonRunner     adapts the current Block onto PlaySession through a narrow PlayerControl protocol
  LessonView, UnitMapView, OnboardingView, ResultsView
  PlaySession      (existing) the play engine. It gains small hooks and no lesson logic.
```

**Rule:** `PlaySession` is already 1,800 lines, so lesson logic does not go into it. It exposes a small `PlayerControl` protocol, and `LessonRunner` drives it through that:
- load a reference
- set wait or play-along mode
- start audition
- start play-along over a bar range
- a callback for graded takes and individual notes

Because `LessonEngine` is pure, the whole journey logic is tested without the UI.

## Milestones

Sizes: **S** is about a day, **M** is 2–4 days, **L** is about a week.

### M0 · Profiles merged ✅
Done. Profiles steps 0–4 ([user-journeys.md](user-journeys.md)) were merged to `main` in `13f6d04`. Every later milestone keys its progress to the active learner. Profiles step 5 (child learners) moves into M10, since it was always waiting on personas.

Still to do by hand before the next TestFlight build: the profiles plan's manual check on the archived app (two learners, switch mid-take, delete the active learner, relaunch).

### M1 · Lesson model and engine: `feature/lessons-core` (M)
**New target `PianoLessons`:**
- `LessonUnit` (not `Unit`, which Foundation already has), `LessonPage` and `Block`. `Block` is a Codable enum: `explain`, `concept`, `wait`, `listen`, `timed`, `songChallenge`.
- A loader that checks every `midi` reference exists and that `unlocks` IDs resolve.
- `LessonEngine`, a state machine:
  - **Inputs:** `notePlayed(pitch)`, `takeGraded(GradeReport)`, `skip`, `askToMoveOn`
  - **Outputs:** the current block, an attempt count, `hintLevel` (0, then 1 after 2 misses on the same note or block, then 2 after 3, which escalates to the persona), and `pageComplete(stars)`
- `Stars.compute(report:, helpUsed:)`: ★ is notes at least 80%; ★★ is notes at least 90% and timing at least 60%; ★★★ is notes at least 95%, timing at least 80%, and no wait mode. The timing score is derived from `TimingSummary.meanIOIError` against the rubric.

**`PianoPadState`:**
- Add `PieceID.lesson(unit:page:block:)`, so takes for each block go into the existing `takes/` layout.
- Add `LessonProgress` (`lessons.json`): page ID → stars, the current block, and completion.

**Tests:**
- engine transitions
- hint and escalation thresholds
- star boundaries
- loader errors
- progress round-trip

**Done when** `swift test` passes, with no UI involved.

### M2 · Clickable keyboard and the computer-keyboard timing window: `feature/keys-input` (S)
- **`KeyboardView`:** mouse down and up on a key go into the same note path as musical typing. A drag across keys plays each one (a glissando).
- **`InputSource`** (`midi`, `mic`, `keys`) is tagged on each note. `Rubric.PlayAlong` gains `keysExtraLateMs` (default 150, read from YAML as `keys_extra_late_ms`). When the source is `keys`, `PlayAlongJudge.Settings` adds it.
- **Grading:** in `keys` mode, rhythm grading uses onsets only and never note lengths. Onsets are already all it uses, so add a test that keeps it that way.

**Done when** a take entered by mouse or typing grades the same as MIDI, and a 120 ms late typed note passes the beginner rubric.

### M3 · Lesson player and Unit 1 pages 1, 2 and 4: `feature/lesson-player` (L)
Built in three branches, each tested on its own:
- **M3a `feature/player-control`:** `PlayerControl` and `PlayerObserver` (`PlaySession+Lessons.swift`), lesson mode (takes saved under the block's `PieceID`, lesson files kept out of recent pieces, practice setup restored afterwards) and clicks-only play-along for lessons. A debug-only ⋯ menu item, "Lesson check", runs a timed block on clicks and shows its stars. No other visible change.
- **M3b:** the Learn tab, `LessonRunner` and page 1.
- **M3c:** pages 2–4 (page 3, the finger-numbers concept card, moved up from M6 so pages unlock in an unbroken chain), finger numbers on the staff, and hints per page or block.

**`PlayerControl` protocol on `PlaySession`:**
- `onNote` and `onTakeGraded` publishers
- `loadReference(url)`
- `setMode(.wait | .playAlong)`
- `startAudition(speed)`
- `startPlayAlong(fromBar:toBar:countInBeats:)`

**Click-only play-along for lessons.** `feature/require-backing-track` made a backing track mandatory, so add `allowsClickOnly` (true when a lesson drives the session) instead of reverting it.

**`LessonRunner`** maps each block onto the session:

| Block | What the runner does |
|---|---|
| `explain` | Text card plus `KeyboardView.highlight` (pulsing keys). A new staff highlight comes from `ScoreRenderer`. It moves on at `advanceOn.note`. |
| `wait` | Loads the MIDI and uses wait mode (`WaitGuide`). Auto-grade finishes the block. |
| `listen` | `startAudition` with keys lit. Continue becomes available when it ends. |
| `timed` | Play-along over clicks with a 4-beat count-in at the block's tempo. A graded result moves the engine on. |

**`LessonView`:**
- the block header ("Play the note C", with a step n/N counter)
- the engraved staff
- the keyboard
- hints
- a pause menu: Restart, Listen, Exit

The finger numbers come from the block's `fingering` array, drawn above the noteheads. This needs a small addition to `ScoreRenderer`.

**Content:** `Lessons/unit1/unit.json`, plus `scripts/make_unit1.py`, which writes the exercise MIDI files deterministically, so the exercises are reviewable as code. That covers pages 1 (C), 2 (D) and 4 (E).

**Where it lives:** a third app tab, **Learn**, next to Practice and Backing Tracks. The existing Practice tab stays as your free-practice and testing mode.

**Done when** pages 1, 2 and 4 play from start to end with MIDI, the mic, typing and mouse, and the stars are saved to the learner.

### M4 · Onboarding: `feature/onboarding` (M)
`OnboardingView` replaces the first-launch add-learner sheet. It runs these steps:
1. welcome
2. learner: name, avatar, adult or child, and played before?
3. at a piano? If not, `inputSource = keys` and the musical-typing map is shown
4. MIDI detection
5. mic permission
6. **guided calibration**: the existing `startCalibration` with new prompts ("find the 2 black keys…") and a pass, warn or fail result
7. teacher
8. goal song

It then lands on Unit 1, page 1.

- `LearnerSettings` gains `persona`, `goalSong` and `inputSource`. They're optional when decoding, so older settings files still load.
- The `offersCalibration` flag goes away; this flow replaces it.
- A local metric records **seconds from launch to the first graded note** in `sessions.json`.

**Done when** a fresh install reaches a graded note on page 1 in under 3 minutes, and every step except mic permission can be skipped.

### M5 · Unit map: `feature/unit-map` (S)
`UnitMapView` shows page cards in the states locked / next / in progress / ★0–3. The goal-song card shows "n of 6 to unlock". The **Continue** button opens `LessonProgress.currentBlock`. The Learn tab opens here for returning learners.

### M6 · Song challenge, concept card and pages 3, 5 and 6: `feature/song-challenge` (L)
**`songChallenge` block**, with four stages: Listen (with backing) → Learn (wait mode, by phrase) → Practise (play-along at 60–80% using the existing replay-bar behaviour) → Perform (100% with `Strictness.keepGoing`, graded once).

**`ResultsView`:** stars, notes / timing / help used, and Retry or Continue.

**`concept` block:** an animated hand (SwiftUI shapes, finger labels 1–5), then a pitch check.

**Content:**
- page 3, Finger Numbers
- page 5, *Hot Cross Buns*
- page 6, *Mary Had a Little Lamb*. `Examples/mary-had-a-little-lamb.mid` already exists.

**Your task:** record two backing tracks in Logic and annotate them in the Backing Tracks tab.

**Done when** the whole unit (6 pages) can be played start to finish and the goal song gives stars.

**As built:**
- **M6a** extended Unit 1 to the full five-finger C position (pages for F and G), added the checkpoint song *Au Clair de la Lune* after the first three notes, and made the goal song the learner's chosen one (`useGoalSong`). Backing uses clicks for now.
- **M6b** (`feature/song-stages`) added the four stages as tabs on song pages. The order is suggested, not enforced. Learn and Practise count as help (at most ★★). Practise plays along at the block's `practiceTempos[0]` (70%). Perform uses `Rubric.PlayAlong.keepGoing` as a lesson-only override. A results card shows stars, notes, timing and help, with Try again, Practise and Continue (once the required stars are reached). Logic is in `PianoLessons/SongStages.swift` (`SongStage`, `SongProgress`, `SongResult`).

**→ This is the demo-ready slice:** M0–M6 covers onboarding, a full unit, and a song with play-along.

### M7 · Fix my mistakes and personas: `feature/fix-my-mistakes` (M)
- **`RemediationPlanner`** (pure): from `GradeReport.flags`, plus `rewindsPerBar`, it picks the worst bar and returns these actions in order:
  1. `loopBar(70%, wait)`
  2. `loopBar(100%)`
  3. `context(bar−1…bar+1)`
  4. `perform`

  These come from the grading design's fixed set of actions.
- **`PlayerControl`** gains bar-range looping (`startPlayAlong(fromBar:toBar:)`, with a repeat count).
- **`Persona` files** (`Personas/alex.yaml`, `Personas/kriti.yaml`) set:
  - how strict the judge is (mapped onto the existing `Strictness` presets)
  - the hint and escalation thresholds
  - the move-on rule (★ or ★★)
  - the tone of the messages

  Kriti's escape route works as already decided: the student asks to move on, or the teacher marks the passage complete.
- **Explaining mistakes:** template messages generated from the flags, such as "You played D instead of E in bar 2, twice. E is finger 3." An LLM rewording of these is a separate, later step, and it never chooses actions.

**Done when** two failed Perform runs lead into the bar-loop drill, and the two personas behave differently on the same take.

**As built** (`feature/fix-my-mistakes`):
- `RemediationPlanner.worstMeasure` weighs wrong and missed notes 2, extra, early and late 1, replays 2; ties go to the earlier bar. `drill(measure:)` gives four steps: **Get the notes** (wait mode), **Slowly, in time** (70% with clicks), **Full speed**, **With the bars around it** (bar ±1, left out for a one-bar song). `BarDrill` counts runs and clean streaks. A clean run passed, replayed nothing and got at least 90% of the notes.
- Bar looping is done by loading just those measures (`MIDISequence.measures(_:)`, `loadLessonBlock(..., measures:)`), so wait mode, play-along, fingering and grading work unchanged. A failed run goes round again by itself after a moment.
- Personas are JSON, not YAML: `Lessons/personas/alex.json` and `kriti.json`, with built-in copies as a fallback. **Alex:** one star passes, gentle judging, the drill is offered after two failed Performs, one clean run per step, at most four runs a step. **Kriti:** two stars, standard judging, the drill opens by itself, two clean runs in a row, no limit. The learner can always press Move on (Kriti's escape route). A teacher marking a passage complete waits for a teacher view.
- The results card says what went wrong ("You played D instead of E in bar 2, twice. E is finger 3."), offers **Fix bar N**, and after enough failed runs **Move on anyway** (flagged, like a skip). Drilling counts as help for the next Perform.
- The teacher can be changed from the unit page (saved in the learner's settings).

### M8 · "It can't hear me": `feature/mic-help` (S) · postponed
**Postponed** (Sam, 2026-10-25): not in the current run. M9 and M10 go ahead without it.

- A mic level pill in `LessonView`. The level is already published.
- The heuristic: if the level stays above the gate for 5 s with no notes detected, show a hint and offer a one-tap recalibration.
- **"I played it right":** saves the take, its WAV and the expected notes into `<learner>/flagged/` in the existing fixture format, as input for grader calibration.

### M9 · Session summary and coming back: `feature/sessions` (M)
- `sessions.json`: start and end, pages, notes learned, minutes.
- A summary sheet when leaving the Learn tab or after 20 minutes idle.
- The next page comes from simple rules: the lowest-star unfinished page, otherwise the next unlocked page.
- The warm-up replays the last `timed` block. If the score drops by more than 20 points, suggest reviewing that page.
- The weekly streak is computed from `sessions.json`. A missed day carries no penalty.

**As built** (`feature/sessions`):
- `PracticeSession` in `<learner>/sessions.json` (newest 500 kept; cleared by Reset progress): start, last activity, pages opened, pages finished, new notes from pages finished for the first time, stars, and the last timed block's note score. A session starts with the first note in the Learn tab and is saved as it goes, so quitting doesn't lose it.
- It ends with a summary sheet when the learner leaves the Learn tab, after 20 minutes with no notes, or with **Finish for today** on the unit page. The sheet shows "Today: C, D, E · 2 pages done · 12 min", stars, the weekly streak and **Next up**, with **Keep going**.
- `Coach.nextPage` (it also drives Continue on the unit page): an unfinished page first (started, or finished with steps skipped), fewest stars first; otherwise the next unlocked page; once everything is done, the starred page with the fewest stars.
- Warm-up: coming back to the Learn tab 30 minutes or more after the last session, the unit page offers the last timed block from a previous session. It runs that block alone, without moving the page's saved position. The result card compares note scores; a drop of more than 20 points suggests reviewing that page.
- Weekly streak: distinct days with a session in the current calendar week ("3 days this week"), on the unit page and in the summary.

### M10 · Child profile: `feature/child-mode` (M)
When `Learner.kind == .child`:
- copy that speaks to the parent during onboarding
- bigger explain cards
- stickers instead of percentages, with stars kept
- Kriti hidden
- a **For grown-ups** panel: minutes this week, notes learned, the page they're stuck on, and one tip

**As built** (`feature/child-mode`):
- Setup speaks to the parent when "A child" is picked (stay close for the first page; For grown-ups is where to check in). The teacher step shows only Alex; children start with Alex whatever was picked earlier.
- Explain and concept cards use a 34-point rounded font with more padding.
- No percentages for children: timed steps, Practise, Perform results and the warm-up say "Amazing!", "Super playing!", "You did it!" or "Good try!" with the stars. Each finished page gives a sticker (`Stickers.forPage`, the crown for the goal song), shown on the finished-page screen and on the page cards.
- The unit page has **For grown-ups** instead of the teacher menu. It shows minutes and days this week, pages done, notes learned, the page they're stuck on (unfinished, or finished with steps skipped), one tip (`GrownUpsTip`, rule-based), and the teacher choice, where Kriti can be picked.

### Later
- **Narration:** read `explain` text aloud with `AVSpeechSynthesizer`, routed through PianoPad's audio engine so the mic stays muted, with word highlighting. It's a per-learner setting.
- An LLM rewording of tutor messages.
- Placement for the "played before" path.
- Unit 2.

## Order and dependencies

```
M0 ─┬─ M1 ── M3 ──┬── M5
    │             ├── M6 ── M7
    └─ M2 ────────┘    │
            M4 (needs M3) ─┘
M9 and M10 after M6, in any order; M8 is postponed
```

M1 and M2 are independent and can run in parallel.

## Risks

- **`PlaySession` keeps growing.** Hold the line with `PlayerControl`. If adding a hook gets messy, first pull the play-along state out into its own type.
- **The mic hears the click track.** Check that the existing playback mute also covers the count-in and metronome clicks during `timed` blocks.
- **Explain blocks advance on any detected C4.** A mic phantom note could skip a block. Require 2 consecutive detections, or a held note, when the input is the mic.
- **Making content takes time.** Generate the exercise MIDI with a script. The only manual work is two backing tracks.

## Beta checklist (TestFlight after M6)

Tell friends: "install, follow setup, do Unit 1". Collect locally, then ask them to export:
- time to the first note
- attempts per block
- where they quit
- stars
- "I played it right" flags
