# Beginner User Journeys

Oct 25, 2026 · Sam

This plan covers the journey for someone sitting at a piano for the first time. It's based on a walkthrough of Simply Piano's beginner course and adapted to what PianoPad already does. The primary learner is an adult teaching themselves. The secondary learner is a child with a parent nearby (`Learner.Kind.child`).

## Decisions

- **Demos use the on-screen keyboard only:** no live-action video and no recorded hands. `KeyboardView` already lights keys during **Listen**, so it can also show "find it" steps.
- **Learners without a piano play on the computer:** musical typing (already built) or by clicking the on-screen keyboard (new).
- **Two ways to hear a piano: the microphone or Bluetooth MIDI.** Setup asks which, by name. The app listens only to Bluetooth MIDI devices; virtual ports (Logic, IAC), USB and network MIDI are ignored. (The `grade` command-line tool still listens to every source, for development.)
- **Public-domain songs only for now.** Unit 1 doesn't depend on any licensed book.
- **Computer-keyboard mode gets a looser timing window.** Typing adds latency and has no key-release events. Add `keys_extra_late_ms` to the rubric's `play_along` and timed checks, alongside the existing `mic_extra_late_ms`. Start at 150 ms for beginners and tune it in the beta. Note lengths are never graded in this mode.
- **Unit 1 is engraved from MIDI** by `Transcriber`, `ScoreLayout` and `ScoreRenderer`. It needs no PDF pages.

## What Simply Piano does

Observed in the walkthrough recording:

1. **Onboarding takes about 40 s and has 8 screens:**
   1. welcome by name
   2. "Are you next to a piano?"
   3. "Played before?"
   4. a promise: "you'll be reading and playing these notes in about 20 minutes"
   5. how often you'll play
   6. goals (pick several)
   7. "Ready!"
   8. **pick your first song as the course's final reward**
2. **The course is a path of nodes:**
   1. intro video
   2. lesson "First 3 Notes"
   3. ★★★ song challenge
   4. "What's next" video
   5. the chosen song
3. **The lesson has three parts:**
   - Learn Middle C and D (12 steps)
   - Finger Numbers (an animated hand)
   - Adding E (11 steps)
4. **Every part follows the same ladder: show → one note → several notes → timing → song.**
   - **Demo:** the staff is shown above a keyboard. Captions say things like "Find the 2 black keys", "This is middle C" and "Your turn".
   - **"Play the note C" ×3** in wait mode, with a hand icon, a mic-level pill, and notes that turn teal as you play them.
   - **"Play the following notes"** with finger numbers, growing to 2 bars.
   - **Timed scroll:** a fixed playhead with the music moving past.
   - The **pause menu** has Play, Restart, Listen and Exit, plus a step counter.
5. **Rewards:**
   - "You learned 2 notes, you're on fire"
   - a weekly streak
   - "Champion! Better than most 4-year-olds" (the kids profile)
6. **The song challenge** offers a choice of 2 songs with 0/3 stars each.
   - The first try is at tempo and scores **1/14 notes, 0% timing**.
   - A toolbar offers speed (0.6–1.2×), Practice (wait mode), Metronome and Finger numbers.
   - In Practice mode the score was 13/14 notes, 10% timing, 60% assists, for ★.
   - The only options after a run are **Retry** (the whole song) or **Continue**.

**What we keep:** the short, personal onboarding; the promise of how long it takes; choosing a reward song up front; the five-step ladder; wait mode before tempo; scores split into notes, timing and help; small celebrations; a gentle weekly streak.

**Where we do better:**
- **Avoid the cliff.** Simply Piano's song challenge starts at tempo. Ours starts in wait mode, then moves to play-along at reduced speed, which already stops and rewinds to the bar.
- **Explain mistakes.** Simply Piano only uses colour. We already say "You played E♭4 · play D4", and the tutor can add which finger to use.
- **Fix only what went wrong.** Simply Piano retries the whole song. We loop the worst bar, then play it again in context (the "loop a bar" action from the grading design).
- **Calibrate the mic.** Simply Piano has none. Ours earns trust that the grading is fair, which matters most for mic-only learners.
- **Strictness per learner:** Kriti or Alex, instead of one voice for everyone.
- **Rewards that fit the learner:** adults see stats, children get stickers. No comparisons with 4-year-olds.

## The journeys

| | Journey | One line |
|---|---|---|
| B0 | First launch | Learner → input → calibration → teacher → goal song → Page 1, in under 3 minutes |
| B1 | The book is the map | Unit pages with states; one click to continue |
| B2 | Lesson page | A list of blocks following the ladder |
| B3 | Finger numbers | A concept card with a pitch check |
| B4 | Adding a note | The same template; proves a lesson is just data |
| B5 | Goal song | Listen → learn → practise → perform, then fix my mistakes |
| B6 | Stuck | Alex or Kriti steps in; the tutor explains |
| B7 | End of session and return | Summary, next page, warm-up, weekly streak |
| B8 | "It can't hear me" | Mic level, recalibrate, "I played it right" |
| B9 | Child profile | The same journeys with different packaging |

### B0 · First launch (target: under 3 minutes to the first graded note)

1. **Welcome:** "Let's get you playing in about 15 minutes." Measure this so the promise stays honest.
2. **Add a learner:** name, avatar, and adult or child. `Learner` and `LearnerStore` already cover this. "Played before?" sets `Learner.level`; `beginner` leads to this path.
3. **"Are you at a piano or keyboard right now?"**
   - *Yes* → go to step 4.
   - *Not right now* → **computer keyboard mode**. Show the musical-typing map over the on-screen keyboard, with a note that clicking keys also works. Everything is graded the same way. Mark the learner's input as `computerKeyboard`. This applies the looser timing window, and the app suggests a real piano later.
4. **Input:**
   - Ask which, by name: **Microphone** (an acoustic piano, or a digital piano through its speakers) or **Bluetooth MIDI** (a digital piano or keyboard with Bluetooth MIDI). Bluetooth shows "Connected: <piano>" or a **Connect a Bluetooth piano…** button that opens macOS's pairing window.
   - Otherwise ask for mic permission: "PianoPad listens to you play. Audio never leaves your Mac."
5. **Microphone setup (mic only).** Choose the input (the built-in microphone by default) and see the output, watch a live level, then **Measure room noise**: 3 seconds of quiet sets the threshold a note must pass to count. (The 10-second C-D-E calibration proved too sensitive for setup; it stays in the ⋯ menu.)

6. **Teacher:** Alex (relaxed, the default for beginners) or Kriti (strict). Either can be changed for each piece later.
7. **Goal song:** choose one of 3–4 public-domain tunes in C position: *Mary Had a Little Lamb*, *Hot Cross Buns*, *Ode to Joy* (simplified) or *Jingle Bells* (chorus). Then show "By the end of Unit 1 you'll play **Mary Had a Little Lamb**."
8. Land on **Page 1, ready to play.** Not on a menu.

**Acceptance:**
- Median time from launch to the first graded note is under 3 minutes.
- The room-noise measurement succeeds first time in at least 80% of quiet rooms.
- Every step can be skipped except choosing the microphone or Bluetooth MIDI.

### B1 · The book is the map

- The structure is **Shelf → Unit 1 "Middle C position" → page thumbnails**.
- Each page is in one of these states: locked, **next** (glowing), in progress, or ★0–3.
- The goal song is the **last page of the unit**, with progress shown ("3 of 6 pages to unlock").
- **Continue** opens the exact block the learner left. Progress is saved per learner (`LearnerHistory`).

**Acceptance:** a returning learner is playing after one click.

### B2 · Lesson page: "Meet Middle C (and D)"

A lesson page is a vertical list of blocks. Each block uses something that already exists.

| # | Block | Experience | Engine |
|---|---|---|---|
| 1 | **Find it** (`explain`) | The on-screen keyboard pulses the 2 black keys, then Middle C. One line of text. Moves on when you play C. | `KeyboardView` highlight; any detected C4 moves on |
| 2 | **Read it** (`explain`) | The C on the engraved staff and the key light up together. | `ScoreRenderer` and `KeyboardView` |
| 3 | **One note** (`wait`) | "Play C" ×3. Each note turns green. | `WaitGuide` |
| 4 | **Introduce D** | Blocks 1–3 again for D, with finger 2. | as above |
| 5 | **Mixed** (`wait`) | C C D C D D C with finger numbers, growing to 2 bars. | `WaitGuide` |
| 6 | **Listen** (`listen`) | The app plays the next exercise with keys lit and a metronome. | existing Listen |
| 7 | **Timed** (`timed`) | 4-beat count-in, playhead at 60 BPM, beginner rubric. | play-along engine with no backing; `Rubrics/beginner.md`, plus `keys_extra_late_ms` on the computer keyboard |
| 8 | **Page done** | "You know 2 notes: C and D." ★ from block 7. | grade report |

**Wrong notes:**
- **Today:** the red circle plus "You played E♭4 · play D4". The right key glows on the on-screen keyboard.
- **After 2 misses on the same note:** an inline hint, e.g. "D is the white key just right of C, finger 2".
- **After 3 misses:** the persona steps in (B6).

**Acceptance:** Page 1 takes an adult 4–6 minutes, and 90% of beginners clear each block within 3 attempts (checked in the TestFlight beta).

### B3 · Concept card: Finger Numbers

- An animated hand labelled 1–5, mapped onto C, D and E on the staff.
- **Check:** "Play the note under finger 3." We can't see which finger was used, but E means they understood.
- Finger numbers stay on for the rest of Unit 1 and can be turned off in the toolbar.

### B4 · Lesson page: "Adding E"

- This is the B2 template with one new note, ending in 2–4 bars of C, D and E: first in wait mode, then timed.
- It proves **a lesson is just data**: new pages need no code changes.

### B5 · Goal song challenge

The last page of the unit has four stages. Each stage unlocks the next.

1. **Listen:** the backing track plays, with keys and notes lit.
2. **Learn:** wait mode, right hand, phrase by phrase, with no backing.
3. **Practise:** play-along at 60–80% tempo. It stops and rewinds to the start of the bar on misses, using the beginner `play_along` thresholds.
4. **Perform:** 100%, no stopping, graded once from start to finish.

**Stars:**

| Stars | Notes | Timing | Other |
|---|---|---|---|
| ★ | at least 80% | — | — |
| ★★ | at least 90% | at least 60% | — |
| ★★★ | at least 95% | at least 80% | no wait-mode help |

The results screen shows **notes / timing / help used**.

**Fix my mistakes**, after each Perform run:
1. Find the bar with the most flagged mistakes in the report.
2. Say what happened: "Bar 3 tripped you up twice. Let's loop it."
3. Loop that bar at 70% in wait mode, then at 100%.
4. Play bars 2–4 in context.
5. Do another Perform run.

**Acceptance:** in at least 70% of beta sessions, a learner who completes Unit 1 earns ★ on the goal song within 3 Perform runs.

### B6 · Stuck: the teacher steps in

**When it starts:** 3 failed attempts at one block, or 2 Perform runs scoring under ★.

| | Alex (relaxed) | Kriti (strict) |
|---|---|---|
| Tone | "No rush, let's slow it down." | "Again. Watch beat 3." |
| Action | Offers 60% speed, or switches to wait mode | Loops the bar until it's clean twice |
| Moving on | At ★, or whenever asked | At ★★, unless the student asks or the teacher marks the passage complete |

**Ask the tutor** is always available. It answers from the take's actual findings, e.g. "You played D instead of E in bar 2, twice. E is your middle finger." As the grading design says, the LLM only words the feedback; it never decides actions.

### B7 · End of session and return

- **Summary:** "Today: C, D, E · 2 pages · 12 min." Then **Next up: Page 3**, from the what-to-practise-next coach.
- **Weekly streak:** "3 days this week". Missing a day costs nothing.
- **Return:**
  1. a 60-second warm-up (the last timed block from the previous session)
  2. then Continue
  3. if the warm-up score falls well short, the coach suggests reviewing one page first

### B8 · "It can't hear me" (mic learners)

- A **mic level pill** is always visible during graded blocks.
- If the level is high but no notes are detected for 5 s: "I'm hearing sound but not clear notes. Try playing a bit firmer, or recalibrate." Recalibration takes one tap.
- If the learner keeps getting flagged at the same spot, offer **"I played it right."** This saves the take, labelled, as a fixture for grader calibration. Mic recordings already go to `~/Music/PianoPad Mic/`.
- Bluetooth MIDI is suggested, never required.

### B9 · Child profile

- **The parent drives B0.** The copy speaks to the parent ("Your child will…").
- **Explain blocks** have bigger visuals and fewer words. Spoken narration is a later, optional setting (see Open questions).
- **Rewards** are stickers and characters. Stars stay; timing percentages are hidden.
- **"For grown-ups" panel:** minutes this week, notes learned, where the child is stuck, and one tip.
- Kriti is hidden by default.

## Unit 1 content: "Middle C position"

All public domain. Reference MIDI is made in Logic and engraved by PianoPad.

| Page | Content | New notes | Blocks |
|---|---|---|---|
| 1 | Meet Middle C | C | explain, wait, timed |
| 2 | Meet D | D | explain, wait, listen, timed |
| 3 | Finger numbers | — | concept and check |
| 4 | Adding E | E | explain, wait, listen, timed |
| 5 | *Hot Cross Buns* | — | listen, wait, timed with backing |
| 6 | 🎯 *Mary Had a Little Lamb* (goal) | — | song challenge (B5) |

Backing tracks for pages 5 and 6 are annotated in the existing Backing Tracks tab (`backing` entry: start, bpm, time signature, key).

## A lesson is data

A unit is a JSON file next to its MIDI files, e.g. `Lessons/unit1/unit.json`. It reuses the annotation overlay's ideas (`backing`, rubric overrides) and adds a list of blocks to each page:

```json
{
  "pageId": "u1p2",
  "title": "Meet D",
  "newNotes": ["D4"],
  "blocks": [
    {"type": "explain", "highlight": ["D4"], "text": "D is the white key between the 2 black keys",
     "advanceOn": {"note": "D4"}},
    {"type": "wait", "midi": "p2-ex1.mid", "fingering": [2, 2, 2], "hand": "R"},
    {"type": "wait", "midi": "p2-ex2.mid", "fingering": [1, 1, 2, 1, 2, 2, 1]},
    {"type": "listen", "midi": "p2-ex3.mid", "tempo": 60},
    {"type": "timed", "midi": "p2-ex3.mid", "tempo": 60, "countInBeats": 4, "rubric": "beginner"}
  ],
  "unlocks": "u1p3"
}
```

The v1 block types are `explain`, `concept`, `wait`, `listen`, `timed` and `songChallenge`. Each maps onto something that already exists: `WaitGuide`, Listen, play-along, and the grader with a rubric. The only new engine is the block sequencer.

## What exists and what's new

| Area | Already in the repo | New for these journeys |
|---|---|---|
| Learners | `Learner` (adult/child, level), `LearnerStore`, per-learner history and settings | Onboarding flow, `input` preference, goal song |
| Input | `MIDIInput`, mic detector with room check, calibration (C4 D4 E4), musical typing | Guided calibration step, level pill, **clickable on-screen keyboard** |
| Playing | `WaitGuide`, Listen with speed, play-along with stop and rewind, tempo | Block sequencer, `explain` and `concept` blocks, count-in for `timed` |
| Feedback | Red circle and "You played X · play Y", grade report, beginner rubric | Hints after 2 misses, stars, notes/timing/help summary |
| Remediation | Design: fixed set of actions, personas | Fix-my-mistakes bar loop, Alex/Kriti rules (B6) |
| Content | MIDI → engraved score | Unit 1 JSON, 6 pages of MIDI, 2 backing tracks |
| Coaching | Takes stored per learner | Session summary, next page, warm-up, weekly streak |

## Build order

| Step | Journeys | Work |
|---|---|---|
| 1 | B2, B4 | Unit JSON and block sequencer (`explain`, `wait`, `listen`, `timed`); Unit 1 pages 1, 2 and 4 |
| 2 | B0 | Onboarding: learner, piano?, input, guided calibration, teacher, goal song; clickable on-screen keyboard |
| 3 | B1 | Unit map with page states and Continue |
| 4 | B5 | Song challenge stages, stars, results screen; pages 5 and 6 with backing |
| 5 | B5, B6 | Fix-my-mistakes loop and persona rules (the fix-my-mistakes drills milestone) |
| 6 | B8 | Level pill, can't-hear-me hints, "I played it right" fixtures (feeds grader calibration) |
| 7 | B7 | Summary, warm-up, next-page coach, weekly streak |
| 8 | B3, B9 | Concept cards, child packaging, grown-ups panel |
| Later | B2, B9 | Optional spoken narration for `explain` blocks (per-learner setting) |

**Beta metrics, per journey:**
- time to first graded note
- page completion
- attempts per block
- where learners quit
- stars on the goal song
- day-2 return
- for mic learners, the share of "I played it right" flags

## Open questions

- [x] Demos: on-screen keyboard only.
- [x] No piano: musical typing and a clickable on-screen keyboard.
- [x] Songs: public domain only for now.
- [x] Computer-keyboard mode gets a looser timing window (see Decisions).
- [x] Spoken narration is later and optional. v1 is text and visuals only. Later, add a per-learner setting that uses the built-in `AVSpeechSynthesizer` (offline, free) to read `explain` text aloud, with a replay button and word highlighting. Route the speech through PianoPad's audio engine (`write(_:toBufferCallback:)`) so the mic is muted during narration, the same way it is during playback. Playing a note or tapping skips the speech. Prefer an Enhanced or Premium voice when one is installed.

## Auto-progress: the timed Continue

Where the learner has just succeeded and there's one sensible next step, Continue fills up and presses itself (`TimedContinueButton`; times in `AutoAdvance`). Children get 1.5× longer. Hovering pauses it; clicking or Return goes at once. Reduce Motion shows a seconds count instead of the fill; with VoiceOver on it never presses itself.

| Where | Waits |
|---|---|
| Setup: welcome, "All set" | 4 s |
| Setup: room noise measured, or Bluetooth piano connected | 2.5 s |
| Setup: after tapping a teacher or goal song | 1.5 s |
| `explain` card with no note to play | 3–8 s, by word count |
| `concept` card with no check | 2 s + reading time |
| `listen` block played through (Listen again stays) | 3 s |
| Song stage done: Listen → Learn → Practise (Practise only with ★ or better) → Perform | 3 s |
| Kriti opens the drill herself (Fix bar N) | 4 s |
| Warm-up fine (no big drop) | 3 s |
| Page done → the coach's next page | 5 s |

**Stays manual:** typing the name, choosing an input, a failed or warned check, any below-threshold result, Perform results (even with stars), Move on anyway, a warm-up drop, the session summary and For grown-ups. `wait` and passed `timed` blocks already move on by themselves after a second.
