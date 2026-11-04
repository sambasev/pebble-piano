# Tutor evals

Measures the quality of the chat tutor (Muse Spark) on four things: **follow-ups**,
**instruction adherence**, **hallucination**, and **latency**. Each case also checks
that the tutor did the task it was asked (the right action, or a refusal). The tutor gets
exactly what the app sends it: the system prompt and reply schema from
`docs/tutor_contract.json`, and a context in the app's format built from the repo's real
fixtures (`Examples/*.mid` scores, grader evidence, progress, app guide).

```sh
python3 evals/tutor/run.py selftest            # tests the scorers on labelled replies (no network)
python3 evals/tutor/run.py replay              # re-scores replies already recorded in docs/ (no network)
MODEL_API_KEY=… python3 evals/tutor/run.py live --trials 3          # 38 cases × 3 against the live model
MODEL_API_KEY=… python3 evals/tutor/run.py live --only gr_,fu_      # just grounding and follow-up cases
ANTHROPIC_API_KEY=… python3 evals/tutor/run.py calibrate --judge claude   # check the judge before trusting it
python3 evals/tutor/run.py live --baseline evals/tutor/results/<run>/summary.json --gate   # CI: exit 1 on regression
```

Each run writes `results/<mode>-<stamp>/`: `report.md` (scorecard, latency table, failures by
rule, every failing reply with the reason), `summary.json` (use it as a later `--baseline`)
and `samples.jsonl` (every reply, raw).

## What's measured

| Metric | How | Examples of a failure |
|---|---|---|
| **task** | per-case expectations (`cases.py` `expect`) | "Play bars 6–7" without `listenPassage 6–7`; answering a code request |
| **adherence** | the system prompt's rules, checked on every reply | over 100 words; quoting "92%, 96 BPM" when the learner didn't ask for numbers; "I've set your speed" (actions run *after* the reply); promising a demo with no action; `startLesson` not last; tempo outside 25–100; listing the notes of a generated exercise; offering Grade take unasked; inventing a goal; for a child, more than 3 sentences, grading words or a non-child action |
| **grounding** (hallucination) | the reply's claims against the facts the context holds | bar 3's notes wrong, or bar 3 called a rest when it has notes; talking about bar 12 of an 8-bar piece; blaming a bar the grader didn't flag; calling a take with mistakes perfect; judging rhythm on a note-by-note take (timing wasn't measured); a `goalDate` with no today's date in context; an `openLesson` ID that doesn't exist; left-hand practice on a one-track piece |
| **follow-ups** | the chips | none offered when expected; >3; >60 chars (the app drops them); in the tutor's voice ("Would you like…"); echoing the question; impossible in the app (a bar that doesn't exist, left hand on a one-track piece); **tapping the first chip gets refused** (live: the runner taps it as a learner would) |
| **latency** | measured on the stream, as the app reads it | first token, **first visible text** (when the app would show the reply, after `"on_topic": true`: what the learner waits for), full reply, output tokens/s; p50/p90/p95; budget p90 ≤ 4 s first text, ≤ 10 s full |
| **LLM judge** (optional) | `judge.py`, 1–5 with every unsupported claim quoted | weak teaching, unhelpful chips, subtler hallucinations rules can't see (an invented "dynamics printed in bars 1–8") |

**Hard** findings fail the sample; **soft** ones are reported but don't fail it. Rates come
with Wilson 95% intervals. With `--trials k`, the report also shows how many cases pass every
trial and which cases are flaky, because the model isn't deterministic.

Replies are scored with deterministic checks first, because they are cheap, repeatable and
safe to gate CI on. The judge is extra. Prefer `--judge claude` (a different model family
from the tutor, so it doesn't grade its own kind of output), and run `calibrate` first. It
grades the hand-labelled replies in `goldens.py`, and if it disagrees with the labels, don't
trust its scores.

## Cases (38)

- **followups** (4): a bar's rhythm, after a wrong note, a one-track piece, theory with nothing open
- **adherence** (14): numbers unasked vs asked, demos, "play then let me try", slow down,
  generated scale, explanation without actions, action order, chord demo, grade on request,
  injected instructions in book text, child note / slower, grown-up summary
- **grounding** (13): a bar's notes, a missing bar, absent dynamics, suggested fingering,
  unmeasured rhythm, which bar went wrong, a rest bar, goal date with and without today, memory
  with and without notes, readiness from slowed takes, best score
- **coaching** (2): the automatic after-take coaching question, a note-by-note pass
- **guardrails** (5): over-refusal (wrist pain, app help, tuning) and refusal (code, role-play)

To add a case, append to `CASES` in `cases.py`. Build its context with `context.practice(...)`,
or another builder, so the facts used for checking come from the same data the tutor sees.
Then add a good and a bad reply to `goldens.py` so `selftest` proves the checks catch it.

## Replay of the recorded replies (no model calls)

`results/replay-baseline/report.md` re-scores the 31 model-only replies in
`docs/tutor_evaluation.json` and the 22 app transcripts in `docs/tutor_live_evaluation.json`.
Those reports show 31/31 and 22/22. Scored against these rules, 7 of the 53 replies fail
(87% overall):

- **Claims an action already happened** (3): "I've played you a major 3rd", "Done — I've set
  your practice speed to 75%", "I've saved it". The prompt forbids this because actions run
  after the reply is shown and can be refused.
- **Invented date** (1): `setGoal` with `goalDate: "2026-11-10"` for "by next week", but the
  context had no today's date.
- **Promised a demo with no action** (1, app end to end, `b5`): "I'll play that slowly for
  you…", and no action ran. The live eval passed it.
- **Over the 100-word limit** (3): 112, 118 and 121 words.

The rules miss one more that a judge would catch: in `ped_04`, the tutor offers to look at
"the dynamics that are printed in bars 1–8", but the context says nothing about dynamics.

Live runs were not done from the cloud session that built this: its network blocks
`api.meta.ai` and it has no key. Run `live` where the key is (your Mac).

## Keeping it in step with the app

Contexts follow `PlaySession+TutorChatContext.swift` and `TutorChatContext.prompt`; the request
follows `ModelTutorChatClient`. The prompt and schema are read from `docs/tutor_contract.json`,
which `TutorContractTests` keeps current, so prompt changes are picked up automatically.
`scorers.promises_action` is a port of `TutorChatReply.promisesAction`.
