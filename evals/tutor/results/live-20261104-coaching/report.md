# Tutor eval: coaching rerun (re-scored: continueLesson accepted)

Model `muse-spark-1.3` · mode `live` · 20261104-225515 · 2 cases × 3 trials = 6 samples · judge `claude:claude-opus-5-5`

## Scorecard

| Metric | Result (95% CI) | What it measures |
|---|---|---|
| **overall** | 67% (30%–90%) | No hard failure on any metric |
| **task** | 83% (44%–97%) | Did what this case asks (right action, refusal, key fact) |
| **adherence** | 100% (61%–100%) | Follows the system prompt: JSON, ≤100 words, no unasked numbers, honest tense, action rules |
| **grounding** | 100% (61%–100%) | No claim the context contradicts (bars, notes, grades, dates, memory) |
| **followups** | 67% (30%–90%) | Chips: ≤3, ≤60 chars, learner's voice, not echoes, possible in the app |
| **hallucination_rate** | 0% (0%–39%) | Answered replies with ≥1 unsupported claim (lower is better) |
| **followup_coverage** | 100% | Answered replies that offer chips |

Consistency: 0/2 cases pass every trial; flaky: co_auto_event, co_wait_mode_pass.

### LLM judge (1–5)

| Grounding | Helpfulness | Teaching | Follow-ups | Replies with unsupported claims |
|---|---|---|---|---|
| 4.33 | 4.17 | 4.00 | 3.17 | 50% |

### Latency (seconds)

| | n | p50 | p90 | p95 | max | p90 budget |
|---|---|---|---|---|---|---|
| First token | 6 | 8.36 | 14.82 | 14.93 | 15.05 |  |
| First visible text | 6 | 9.12 | 15.80 | 15.94 | 16.07 | ≤ 4s ❌ |
| Full reply | 6 | 9.86 | 16.85 | 17.04 | 17.23 | ≤ 10s ❌ |
| Output tokens/s | 6 | 790.83 | 871.94 | 886.90 | 901.86 |  |

## By category

| Category | Samples | Pass |
|---|---|---|
| coaching | 6 | 67% |

## Failures by rule

| Rule | Count |
|---|---|
| `task.action_field` | 2 |
| `followups.infeasible` | 2 |
| `grounding.hand_tracks (soft)` | 1 |

## Cases

| Case | Category | Pass | Latency | Findings |
|---|---|---|---|---|
| `co_auto_event` #1 | coaching | ✅ | 17.2s | (soft) grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `co_auto_event` #2 | coaching | ❌ | 8.5s | task.action_field: practicePassage fromBar: expected '3–4', got 1; task.action_field: practicePassage toBar: expected '4–5', got 8; followups.infeasible: left-hand chip on a one-track piece: 'Left hand only please' |
| `co_auto_event` #3 | coaching | ✅ | 16.5s | OK |
| `co_wait_mode_pass` #1 | coaching | ✅ | 8.0s | OK |
| `co_wait_mode_pass` #2 | coaching | ✅ | 11.2s | OK |
| `co_wait_mode_pass` #3 | coaching | ❌ | 7.5s | followups.infeasible: left-hand chip on a one-track piece: 'Try left hand only' |

## Failing replies

### `co_auto_event`

- **Question:** Tell me how that attempt went, like my piano teacher, and guide me into the selected exercise.
- **Reply:** "Lovely careful run — you got almost all the notes and kept the beat nice and steady. Just two little slips to fix: the G in bar 4 came out as F, and the E in bar 7 didn't sound. I'll set up the full 8 bars again at full speed, then it's your turn — sing the steps as you play."
- **Actions:** ['practicePassage'] · **Chips:** ['Can we do bars 3-4 slower?', 'Play bar 4 for me first', 'Left hand only please']
- ❌ task.action_field: practicePassage fromBar: expected '3–4', got 1
- ❌ task.action_field: practicePassage toBar: expected '4–5', got 8
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Left hand only please'

### `co_wait_mode_pass`

- **Question:** Tell me how that attempt went, like my piano teacher, and guide me into the selected exercise.
- **Reply:** "Lovely clean run — you found all the notes from C up to G and back, with no extras. That was note-by-note, so we haven't checked your timing yet. I'll set up the same warm-up in time at a gentler speed, then it's your turn — count steadily and keep that wrist loose."
- **Actions:** ['practicePassage'] · **Chips:** ['Stay note-by-note for now', 'Try left hand only', 'Back to full speed']
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Try left hand only'

