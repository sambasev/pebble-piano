# Triage: live run 2026-11-04

`muse-spark-1.3`, 44 cases × 3 trials = 132 samples, judge `claude-opus-5-5`.
Every failing reply in `samples.jsonl` was read by hand. The model was not called again:
`report.md` / `summary.json` are the **same replies re-scored** with the fixed scorers
(`python3 evals/tutor/results/live-20261104/rescore.py`). The original scoring is in
`report.as-run.md` / `summary.as-run.json`.

| | as run | after triage (95% CI) |
|---|---|---|
| overall | 71% (63–78%) | **86% (79–91%)** |
| task | 95% (89–97%) | 95% (89–97%) |
| adherence | 95% (89–97%) | 95% (89–97%) |
| grounding | 80% (73–86%) | **95% (89–97%)** |
| follow-ups | 96% (91–98%) | 98% (95–100%) |
| hallucination rate | 21% (14–29%) | **6% (3–11%)** |
| follow-up answerable | 100% (76–100%, n=12) | same |

Latency doesn't depend on scoring, so it is unchanged. **It misses the budget**: first visible
text p50 6.3 s / p90 9.4 s (budget p90 ≤ 4 s), full reply p50 7.0 s / p90 10.7 s (budget ≤ 10 s).
Judge averages: grounding 4.69, helpfulness 4.36, teaching 3.80, follow-ups 3.92, and 19% of
replies have at least one unsupported claim. Calibration: the judge agreed with 25/28 labels.

## Real tutor failures (rules), by cause

**1. Says it already saved the goal (`adherence.claims_done`): 5 of 6 goal replies.**
Actions run after the reply is shown and can be refused, so the contract forbids the past tense.
This happens on almost every `setGoal`: `gr_goal_with_date` 3/3, `gr_goal_no_date` 2/3.
> "Lovely goal — I've saved it for next Friday!" (`gr_goal_with_date` #1)

**2. Makes up a goal date (`grounding.invented_date`, `task.action_field`): 3/3.**
The context has no today's date, but `goalDate` is set to `2026-11-13` every time. The model uses its own
clock, and the app can't check that date.
> `setGoal goalDate "2026-11-13"`: "I've saved it for next Friday!" (`gr_goal_no_date` #3)

The judge also catches a contradiction that the rules don't: the reply says the piece has no left hand,
but the saved goal still reads "hands together", and #3 offers to "add a left hand if you like".

**3. Gives grader numbers to a grown-up who didn't ask (`adherence.no_numbers`): 2/3.**
The grown-up chip asks for time practised, what's going well, where the child is stuck, and one tip.
It doesn't ask for numbers, and the prompt says never to quote percentages unless asked.
> "On Mary Had a Little Lamb she's improved from 61% to 92% correct…" (`ia_grown_up` #1)

Both replies also call the child "she"/"her", but the context gives only "Child learner, age 7". The judge
caught this; no rule checks for it.

**4. Left-hand chip on a one-track piece (`followups.infeasible`): 2.**
> chips `["Play it slower", "Let me try left hand", …]` on Mary, which has one right-hand track (`ia_listen_then_try` #2; also `gr_timing_unassessed` #2 "Slower, left hand only")

## Scorer false positives fixed (scorers.py, with goldens)

Before the fix, each new "good" golden failed (33/37). After it, selftest passes 37/37.

- **`grounding.hand_tracks`: 21 hard → soft when the action has hand "R" and the reply says nothing about hands.**
  All 21 hits were `hand: "R"` on Mary, which has one treble track and is played by the right hand. No reply said anything
  about hands (e.g. `ia_listen_passage` #1: "I'll play bars 6-7 for you now — listen for that stepwise
  climb E-F-G then back down."). On a one-track piece the app throws the hand away. In
  `PlaySession+TutorChatActions.swift`, the in-lesson listen path uses
  `full.hasTwoHands && action.hand != .both ? action.hand : nil`, and the practice/listen path maps a one-hand
  request to all notes ("all its notes (the file has one track)"). The learner hears and practises exactly
  what was asked, and nothing false is shown, so this isn't a hallucination the learner can see. The README failure, "left-hand
  practice on a one-track piece", is still **hard**: hand "L" is always hard, and so is "R" when the
  reply talks about hands ("just the right hand…, without the left hand"). Goldens: `ia_listen_passage`
  good (silent R), bad (L), bad (R + hand claim). Soft findings still show in the report (21), so a
  prompt fix can still be measured.
- **`grounding.timing_unassessed`**: the reply that said timing "wasn't tracked, so I can't tell if your rhythm
  was steady" was flagged for judging rhythm. "tracked" is now accepted alongside checked/assessed/measured.
  Golden: `gr_timing_unassessed` good.
- **`followups.echo`**: the chip "How should I finger bar 4?" after "How should I finger bar 12?" (an 8-bar
  piece) was flagged as an echo. It's a useful redirect to a bar that exists. A chip whose bars differ from the question's
  is no longer an echo. Goldens: `gr_missing_bar` good (bar 4) and bad (bar 12 still caught).
- **`followups.infeasible`**: "Try left hand too" after a G-major **scale** exercise was flagged because
  the open piece has one track. A `practiceExercise` has its own hand, so the left-hand scale is possible.
  The rule now skips replies that set up a generated exercise. Golden: `ia_scale_exercise` good.

## Not tutor failures, not fixed here (harness/case issues)

- **Coaching cases (`co_auto_event`, `co_wait_mode_pass`), 0/6, are a harness bug.** `cases._coaching`
  always adds `Current exercise: Mary Had a Little Lamb, printed bars 1–8, 100%, hand LR`, and the
  app's coaching question says "guide me into **the selected exercise**".
  - In `co_wait_mode_pass` the open score is the 3-bar Five-Finger Warm-up. The tutor set up "Mary… bars 1–8",
    as the context told it to, and was flagged for bars that don't exist (`action_bar_exists`, `bar_exists`).
  - In `co_auto_event` the case expects a passage around bar 4 (3–5), but the context selects bars
    1–8. Trials #2 and #3 followed the context exactly. #1 picked 4–7.
  Fixing this means changing the cases' contexts, which changes what they measure. I didn't make that change
  in this run. Suggested fix: build the current exercise from each case, then rerun `--only co_`.
  The judge still found real problems here: praise for things the grader doesn't measure
  ("Lovely singing tone", "nice and clean with good fingering", "nice steady fingers").
- **`grounding.bar_notes` on `fu_one_track_hands` #1** is a false positive I left alone. "Keep your right hand in one
  C-position with thumb on C4 and pinky on G4, so fingers 3-3-4-5 do bars 6" describes hand position, not
  bar 6's notes. The check matches note names in any sentence that names exactly one bar, and a narrower fix
  would be guesswork.
- **`task.actions` on `rc_played_it_right` #3**: `highlight` bar 4 came before `markPlayedRight`. The case expects
  the actions to start with `markPlayedRight`. The reply is fine and the highlight does no harm. This is borderline:
  the case is strict about order, so I left it.

## What only the judge sees (rules miss these)

- **Praise for what wasn't measured**: tone, fingering, "steady" on note-by-note takes (coaching cases;
  `gr_not_ready` #2/#3 "Your slower runs are sounding nice and steady" when only 3 of 5 passed).
- **`ia_grade_when_asked`, judge grounding 2–3 in all 3 trials**: "Well done for playing it through!" when
  only 14 of the piece's 26 notes were recorded, plus a made-up "Grade take button".
- **Made-up details about the learner**: the child called "she"; a current teacher named "Alex" (`gd_app_help` #1).
- **Two rule misses worth closing later**:
  - `claims_done` doesn't catch "I've flagged your take" (`rc_played_it_right` #1).
  - `no_numbers` only runs when the context has a graded take, so "you're up to 85%" (`rc_plan_session` #3,
    from progress trends) isn't caught.

## Coaching rerun (after the harness fix in d747697)

`--only co_ --trials 3 --judge claude`, results in `results/live-20261104-coaching/`. Each coaching
case now names its own current exercise and the app's "Deterministic next step", in the app's format
(`PlaySession+TutorChatContext.swift:50`). Selftest passes 41/41. **3 of 6 pass** (overall 50%, task 67%, adherence 100%,
grounding 100%, follow-ups 67%). Judge: grounding 4.33, helpfulness 4.17, teaching 4.00, follow-ups 3.17,
and 3 of 6 replies have an unsupported claim. All 3 failures are real; there were no scorer false positives, and no scorer changed.

- **Ignores the app's next step (`co_auto_event` #2).** The next step is bars 3–4 at 70%, but the tutor set up
  "the full 8 bars again at full speed" (`practicePassage 1–8, 100%`). The judge gave it helpfulness 2.
- **Says one thing and does another (`co_auto_event` #3).** "Let's zoom in on bars 3-4 a bit slower… I'll set
  that up now", but the only action is `continueLesson`, so bars 3–4 are never set up. The promise check
  doesn't catch it, because a different action is present.
- **Left-hand chip on a one-track piece again** (`co_auto_event` #2 "Left hand only please",
  `co_wait_mode_pass` #3 "Try left hand only"). This is the same cause as failure 4 above.

When it follows the next step it does well: `co_auto_event` #1 set bars 3–4 at 70%, and `co_wait_mode_pass` set the warm-up
timed at 80% in 3/3 trials, saying correctly that timing hadn't been checked yet. The judge still finds the
praise for things the grader doesn't measure: "Lovely singing tone" (#1), and "tidy fingering" in 2 of 3 `co_wait_mode_pass`
replies. #2 also says "bars 1-3 hands together" on a one-track piece. That isn't a rule failure: hand LR is
allowed, and `hand_tracks` only checks R/L. Latency in this small rerun (n=6) is first visible text
p50 9.1 s / p90 15.8 s and full reply p50 9.9 s / p90 16.8 s, slower than the main run.

### Coaching rerun: one verdict reversed (parent session)

`co_auto_event` #3 used `continueLesson`. In the app that starts the tutor's deterministic next
step (`startTutorExercise`, `PlaySession+TutorChatActions.swift:235`), here bars 3–4 at 70%: the
right exercise, and the reply's "bars 3-4 a bit slower… I'll set that up" is accurate. The case
now accepts `continueLesson` or `practicePassage` 3–4 (goldens added). Re-scored: 4 of 6 pass
(67%). The remaining two are real: #2 replays bars 1–8 at full speed instead of the chosen step,
and two replies offer left-hand practice on one-track pieces.
