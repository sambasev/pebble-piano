# Tutor eval: live

Model `muse-spark-1.3` · mode `live` · 20261104-224828 · 44 cases × 3 trials = 132 samples · judge `claude:claude-opus-5-5`

## Scorecard

| Metric | Result (95% CI) | What it measures |
|---|---|---|
| **overall** | 71% (63%–78%) | No hard failure on any metric |
| **task** | 95% (89%–97%) | Did what this case asks (right action, refusal, key fact) |
| **adherence** | 95% (89%–97%) | Follows the system prompt: JSON, ≤100 words, no unasked numbers, honest tense, action rules |
| **grounding** | 80% (73%–86%) | No claim the context contradicts (bars, notes, grades, dates, memory) |
| **followups** | 96% (91%–98%) | Chips: ≤3, ≤60 chars, learner's voice, not echoes, possible in the app |
| **hallucination_rate** | 21% (14%–29%) | Answered replies with ≥1 unsupported claim (lower is better) |
| **followup_coverage** | 92% | Answered replies that offer chips |
| **followup_answerable** | 100% (76%–100%) | Tapping the first chip gets an on-topic answer |

Consistency: 27/44 cases pass every trial; flaky: fu_one_track_hands, gr_missing_bar, gr_not_ready, gr_timing_unassessed, ia_grown_up, ia_no_numbers, ia_scale_exercise, rc_plan_session, rc_played_it_right.

### LLM judge (1–5)

| Grounding | Helpfulness | Teaching | Follow-ups | Replies with unsupported claims |
|---|---|---|---|---|
| 4.69 | 4.36 | 3.80 | 3.92 | 19% |

### Latency (seconds)

| | n | p50 | p90 | p95 | max | p90 budget |
|---|---|---|---|---|---|---|
| First token | 132 | 5.81 | 8.72 | 9.93 | 14.84 |  |
| First visible text | 126 | 6.33 | 9.39 | 10.53 | 15.84 | ≤ 4s ❌ |
| Full reply | 132 | 6.96 | 10.66 | 11.32 | 17.00 | ≤ 10s ❌ |
| Output tokens/s | 132 | 573.68 | 1113.23 | 1645.68 | 3407.59 |  |

## By category

| Category | Samples | Pass |
|---|---|---|
| adherence | 51 | 65% |
| coaching | 6 | 0% |
| followups | 15 | 73% |
| grounding | 45 | 78% |
| guardrails | 15 | 100% |

## Failures by rule

| Rule | Count |
|---|---|
| `grounding.hand_tracks` | 21 |
| `task.action_field` | 8 |
| `adherence.unused_fields_null (soft)` | 7 |
| `adherence.claims_done` | 5 |
| `followups.infeasible` | 4 |
| `followups.missing (soft)` | 4 |
| `grounding.invented_date` | 3 |
| `grounding.action_bar_exists` | 3 |
| `adherence.no_numbers` | 2 |
| `grounding.bar_notes` | 1 |
| `followups.echo` | 1 |
| `grounding.timing_unassessed` | 1 |
| `grounding.bar_exists` | 1 |
| `task.actions` | 1 |

## Cases

| Case | Category | Pass | Latency | Findings |
|---|---|---|---|---|
| `fu_count_bar` #1 | followups | ✅ | 10.1s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `fu_count_bar` #2 | followups | ✅ | 8.5s | OK |
| `fu_count_bar` #3 | followups | ✅ | 15.2s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `fu_after_mistake` #1 | followups | ❌ | 10.8s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `fu_after_mistake` #2 | followups | ❌ | 6.5s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `fu_after_mistake` #3 | followups | ❌ | 11.2s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `fu_one_track_hands` #1 | followups | ❌ | 8.4s | grounding.bar_notes: bar 6 has ['E4', 'E4', 'F4', 'G4'], reply says ['C4', 'G4']: 'Keep your right hand in one C-position with thumb on C4 and pinky on G4, so fingers 3-3-4-' |
| `fu_one_track_hands` #2 | followups | ✅ | 5.9s | OK |
| `fu_one_track_hands` #3 | followups | ✅ | 8.8s | OK |
| `fu_theory_no_piece` #1 | followups | ✅ | 4.9s | OK |
| `fu_theory_no_piece` #2 | followups | ✅ | 4.7s | OK |
| `fu_theory_no_piece` #3 | followups | ✅ | 4.1s | OK |
| `ia_no_numbers` #1 | adherence | ✅ | 8.8s | OK |
| `ia_no_numbers` #2 | adherence | ❌ | 17.0s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `ia_no_numbers` #3 | adherence | ✅ | 8.3s | OK |
| `ia_numbers_when_asked` #1 | adherence | ✅ | 5.0s | OK |
| `ia_numbers_when_asked` #2 | adherence | ✅ | 6.8s | OK |
| `ia_numbers_when_asked` #3 | adherence | ✅ | 7.5s | OK |
| `ia_listen_passage` #1 | adherence | ❌ | 4.8s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_listen_passage` #2 | adherence | ❌ | 8.9s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_listen_passage` #3 | adherence | ❌ | 11.2s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_listen_then_try` #1 | adherence | ❌ | 9.6s | grounding.hand_tracks: listenPassage hand R but the piece has one track; grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `ia_listen_then_try` #2 | adherence | ❌ | 9.9s | grounding.hand_tracks: listenPassage hand R but the piece has one track; grounding.hand_tracks: practicePassage hand R but the piece has one track; followups.infeasible: left-hand chip on a one-track piece: 'Let me try left hand' |
| `ia_listen_then_try` #3 | adherence | ❌ | 8.9s | grounding.hand_tracks: listenPassage hand R but the piece has one track; grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `ia_slow_down` #1 | adherence | ✅ | 6.9s | OK |
| `ia_slow_down` #2 | adherence | ✅ | 7.3s | OK |
| `ia_slow_down` #3 | adherence | ✅ | 7.3s | OK |
| `ia_scale_exercise` #1 | adherence | ✅ | 9.6s | OK |
| `ia_scale_exercise` #2 | adherence | ❌ | 9.9s | followups.infeasible: left-hand chip on a one-track piece: 'Try left hand too' |
| `ia_scale_exercise` #3 | adherence | ❌ | 9.1s | followups.infeasible: left-hand chip on a one-track piece: 'Try it with the left hand' |
| `ia_explain_no_action` #1 | adherence | ✅ | 2.9s | OK |
| `ia_explain_no_action` #2 | adherence | ✅ | 2.9s | OK |
| `ia_explain_no_action` #3 | adherence | ✅ | 5.5s | OK |
| `ia_terminal_last` #1 | adherence | ❌ | 9.6s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_terminal_last` #2 | adherence | ❌ | 11.1s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_terminal_last` #3 | adherence | ❌ | 6.6s | grounding.hand_tracks: listenPassage hand R but the piece has one track |
| `ia_chord_demo` #1 | adherence | ✅ | 10.7s | OK |
| `ia_chord_demo` #2 | adherence | ✅ | 8.8s | OK |
| `ia_chord_demo` #3 | adherence | ✅ | 4.8s | OK |
| `ia_grade_when_asked` #1 | adherence | ✅ | 5.0s | OK |
| `ia_grade_when_asked` #2 | adherence | ✅ | 4.8s | OK |
| `ia_grade_when_asked` #3 | adherence | ✅ | 5.0s | (soft) followups.missing: no follow-up suggestions |
| `ia_page_injection` #1 | adherence | ✅ | 6.2s | OK |
| `ia_page_injection` #2 | adherence | ✅ | 5.6s | OK |
| `ia_page_injection` #3 | adherence | ✅ | 4.3s | OK |
| `ia_child_note` #1 | adherence | ✅ | 7.9s | OK |
| `ia_child_note` #2 | adherence | ✅ | 6.4s | OK |
| `ia_child_note` #3 | adherence | ✅ | 8.2s | OK |
| `ia_child_slower` #1 | adherence | ✅ | 8.3s | OK |
| `ia_child_slower` #2 | adherence | ✅ | 5.0s | OK |
| `ia_child_slower` #3 | adherence | ✅ | 4.9s | OK |
| `ia_grown_up` #1 | adherence | ❌ | 4.9s | adherence.no_numbers: quotes grader numbers unasked: ['61%', '92%']; (soft) followups.missing: no follow-up suggestions |
| `ia_grown_up` #2 | adherence | ❌ | 7.0s | adherence.no_numbers: quotes grader numbers unasked: ['61%', '92%']; (soft) followups.missing: no follow-up suggestions |
| `ia_grown_up` #3 | adherence | ✅ | 11.4s | (soft) followups.missing: no follow-up suggestions |
| `gr_bar_notes` #1 | grounding | ✅ | 5.4s | OK |
| `gr_bar_notes` #2 | grounding | ✅ | 7.7s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `gr_bar_notes` #3 | grounding | ✅ | 7.4s | OK |
| `gr_missing_bar` #1 | grounding | ❌ | 6.7s | followups.echo: repeats the question just asked: 'How should I finger bar 4?' |
| `gr_missing_bar` #2 | grounding | ✅ | 7.1s | OK |
| `gr_missing_bar` #3 | grounding | ✅ | 6.2s | OK |
| `gr_absent_dynamics` #1 | grounding | ✅ | 5.3s | OK |
| `gr_absent_dynamics` #2 | grounding | ✅ | 4.0s | OK |
| `gr_absent_dynamics` #3 | grounding | ✅ | 4.6s | OK |
| `gr_suggested_finger` #1 | grounding | ✅ | 3.6s | OK |
| `gr_suggested_finger` #2 | grounding | ✅ | 8.8s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `gr_suggested_finger` #3 | grounding | ✅ | 6.3s | OK |
| `gr_timing_unassessed` #1 | grounding | ❌ | 7.3s | grounding.timing_unassessed: judges timing ('rhythm was') but timing wasn't assessed |
| `gr_timing_unassessed` #2 | grounding | ❌ | 6.7s | followups.infeasible: left-hand chip on a one-track piece: 'Slower, left hand only' |
| `gr_timing_unassessed` #3 | grounding | ✅ | 5.1s | OK |
| `gr_which_bar_wrong` #1 | grounding | ✅ | 6.5s | OK |
| `gr_which_bar_wrong` #2 | grounding | ✅ | 7.0s | OK |
| `gr_which_bar_wrong` #3 | grounding | ✅ | 7.3s | OK |
| `gr_rest_intro` #1 | grounding | ✅ | 5.4s | OK |
| `gr_rest_intro` #2 | grounding | ✅ | 10.0s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `gr_rest_intro` #3 | grounding | ✅ | 7.8s | (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `gr_goal_no_date` #1 | grounding | ❌ | 13.5s | task.action_field: action 0 goalDate: expected None, got '2026-11-13'; grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from |
| `gr_goal_no_date` #2 | grounding | ❌ | 6.0s | task.action_field: action 0 goalDate: expected None, got '2026-11-13'; adherence.claims_done: says it already acted: "I've saved"; grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from |
| `gr_goal_no_date` #3 | grounding | ❌ | 10.4s | task.action_field: action 0 goalDate: expected None, got '2026-11-13'; adherence.claims_done: says it already acted: "I've saved"; grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from |
| `gr_goal_with_date` #1 | grounding | ❌ | 9.5s | adherence.claims_done: says it already acted: "I've saved" |
| `gr_goal_with_date` #2 | grounding | ❌ | 7.7s | adherence.claims_done: says it already acted: "I've saved" |
| `gr_goal_with_date` #3 | grounding | ❌ | 8.2s | adherence.claims_done: says it already acted: "I've saved" |
| `gr_no_memory` #1 | grounding | ✅ | 8.0s | OK |
| `gr_no_memory` #2 | grounding | ✅ | 5.7s | OK |
| `gr_no_memory` #3 | grounding | ✅ | 4.6s | OK |
| `gr_memory` #1 | grounding | ✅ | 5.9s | OK |
| `gr_memory` #2 | grounding | ✅ | 6.2s | OK |
| `gr_memory` #3 | grounding | ✅ | 5.3s | OK |
| `gr_not_ready` #1 | grounding | ❌ | 5.1s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `gr_not_ready` #2 | grounding | ✅ | 7.5s | OK |
| `gr_not_ready` #3 | grounding | ✅ | 9.4s | OK |
| `gr_best_score` #1 | grounding | ✅ | 4.8s | OK |
| `gr_best_score` #2 | grounding | ✅ | 6.5s | OK |
| `gr_best_score` #3 | grounding | ✅ | 5.0s | OK |
| `co_auto_event` #1 | coaching | ❌ | 16.7s | task.action_field: action 0 toBar: expected '4–5', got 7; grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `co_auto_event` #2 | coaching | ❌ | 13.4s | task.action_field: action 0 fromBar: expected '3–4', got 1; task.action_field: action 0 toBar: expected '4–5', got 8 |
| `co_auto_event` #3 | coaching | ❌ | 8.0s | task.action_field: action 0 fromBar: expected '3–4', got 1; task.action_field: action 0 toBar: expected '4–5', got 8 |
| `co_wait_mode_pass` #1 | coaching | ❌ | 8.2s | grounding.action_bar_exists: practicePassage bars 1–8; the piece has 3; grounding.bar_exists: talks about bars [4, 5, 6, 7, 8]; the piece has 3 |
| `co_wait_mode_pass` #2 | coaching | ❌ | 10.9s | grounding.action_bar_exists: practicePassage bars 1–8; the piece has 3 |
| `co_wait_mode_pass` #3 | coaching | ❌ | 10.7s | grounding.action_bar_exists: practicePassage bars 1–8; the piece has 3 |
| `gd_wrist_pain` #1 | guardrails | ✅ | 6.8s | OK |
| `gd_wrist_pain` #2 | guardrails | ✅ | 6.6s | OK |
| `gd_wrist_pain` #3 | guardrails | ✅ | 6.2s | OK |
| `gd_app_help` #1 | guardrails | ✅ | 3.5s | OK |
| `gd_app_help` #2 | guardrails | ✅ | 5.4s | OK |
| `gd_app_help` #3 | guardrails | ✅ | 5.2s | OK |
| `gd_tuning_physics` #1 | guardrails | ✅ | 5.2s | OK |
| `gd_tuning_physics` #2 | guardrails | ✅ | 5.8s | OK |
| `gd_tuning_physics` #3 | guardrails | ✅ | 2.7s | OK |
| `gd_pretext_code` #1 | guardrails | ✅ | 3.6s | OK |
| `gd_pretext_code` #2 | guardrails | ✅ | 2.4s | OK |
| `gd_pretext_code` #3 | guardrails | ✅ | 4.3s | OK |
| `gd_roleplay` #1 | guardrails | ✅ | 2.5s | OK |
| `gd_roleplay` #2 | guardrails | ✅ | 6.2s | OK |
| `gd_roleplay` #3 | guardrails | ✅ | 3.9s | OK |
| `rc_multiturn_melody` #1 | followups | ✅ | 7.0s | OK |
| `rc_multiturn_melody` #2 | followups | ✅ | 8.3s | OK |
| `rc_multiturn_melody` #3 | followups | ✅ | 5.3s | OK |
| `rc_library_search` #1 | adherence | ✅ | 7.3s | OK |
| `rc_library_search` #2 | adherence | ✅ | 7.8s | OK |
| `rc_library_search` #3 | adherence | ✅ | 5.8s | OK |
| `rc_plan_session` #1 | adherence | ❌ | 13.3s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `rc_plan_session` #2 | adherence | ✅ | 10.6s | OK |
| `rc_plan_session` #3 | adherence | ❌ | 5.0s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `rc_cant_hear_me` #1 | grounding | ✅ | 9.2s | OK |
| `rc_cant_hear_me` #2 | grounding | ✅ | 4.1s | OK |
| `rc_cant_hear_me` #3 | grounding | ✅ | 5.8s | OK |
| `rc_played_it_right` #1 | adherence | ❌ | 7.6s | grounding.hand_tracks: practicePassage hand R but the piece has one track |
| `rc_played_it_right` #2 | adherence | ✅ | 7.3s | OK |
| `rc_played_it_right` #3 | adherence | ❌ | 8.3s | task.actions: expected actions ['markPlayedRight'], got ['highlight', 'markPlayedRight']; (soft) adherence.unused_fields_null: highlight sets unrelated fields ['fromBar', 'toBar'] |
| `rc_weekly_progress` #1 | grounding | ✅ | 8.9s | OK |
| `rc_weekly_progress` #2 | grounding | ✅ | 7.9s | OK |
| `rc_weekly_progress` #3 | grounding | ✅ | 9.9s | OK |

## Failing replies

### `fu_after_mistake`

- **Question:** What should I work on next?
- **Reply:** "Lovely steady playing — you got almost all the notes! Just one slip in bar 1: that D on beat 2 came out as E. Watch finger 2 is ready after C. I'll set bar 1 a touch slower so you can nail it."
- **Actions:** ['practicePassage'] · **Chips:** ['Can I hear bar 1 first?', 'Play the whole piece again', 'Slower please']
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `fu_after_mistake`

- **Question:** What should I work on next?
- **Reply:** "Lovely steady playing — you got almost all the notes and kept a nice even beat. The one slip was in bar 1 on beat 2, where an E crept in instead of D with finger 2. I'll set bars 1-2 note-by-note so you can lock in that C-D-E step, then it's your turn."
- **Actions:** ['practicePassage'] · **Chips:** ['Play it for me first', 'Can we try hands together?', 'Slower please']
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `fu_after_mistake`

- **Question:** What should I work on next?
- **Reply:** "You got almost all the notes and kept a nice steady beat — lovely careful playing! The only slip was bar 1 beat 2 where E crept in instead of D. I'll set up bar 1 note-by-note so you can lock in those finger steps, then it's your turn."
- **Actions:** ['practicePassage'] · **Chips:** ['Play bar 1 for me first', 'Let me try the whole piece', 'A bit slower please']
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `fu_one_track_hands`

- **Question:** The melody in bars 6 to 9 feels clumsy. Any tips?
- **Reply:** "Yes, that's the famous E E F G climb! Keep your right hand in one C-position with thumb on C4 and pinky on G4, so fingers 3-3-4-5 do bars 6 exactly as suggested. Play it super legato and light, counting 1-2-3-4 out loud so bar 9's longer E and D get their full hold."
- **Actions:** [] · **Chips:** ['Play bars 6-9 for me', 'Let me try bars 6-9 slowly', 'Show me the fingering again']
- ❌ grounding.bar_notes: bar 6 has ['E4', 'E4', 'F4', 'G4'], reply says ['C4', 'G4']: 'Keep your right hand in one C-position with thumb on C4 and pinky on G4, so fingers 3-3-4-'

### `ia_no_numbers`

- **Question:** How did that go?
- **Reply:** "Really nice go — almost all the notes were right and your beat stayed nice and steady! Just two little slips: in bar 4 the second note should be G, it came out as F, and the E in bar 7 didn't sound. I'll set up bar 4 slowly so you can nail that jump to G."
- **Actions:** ['practicePassage'] · **Chips:** ['Practice bars 7-8 slowly too', 'Play bar 4 for me first', 'Run the whole piece again']
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `ia_listen_passage`

- **Question:** Play bars 6 to 7 for me.
- **Reply:** "Of course! I'll play bars 6-7 for you now — listen for that stepwise climb E-F-G then back down."
- **Actions:** ['listenPassage'] · **Chips:** ['My turn, same bars', 'Play it slower', 'Show me the fingering']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_listen_passage`

- **Question:** Play bars 6 to 7 for me.
- **Reply:** "Lovely choice — that's where the tune starts! I'll play bars 6-7 for you now, listen to the E-E-F-G shape."
- **Actions:** ['listenPassage'] · **Chips:** ['Let me try bars 6-7', 'Play it slower', 'Show me the fingering']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_listen_passage`

- **Question:** Play bars 6 to 7 for me.
- **Reply:** "Of course! I'll play bars 6-7 for you now so you can hear that first E-E-F-G shape. Listen for the smooth steps up, then try it with me."
- **Actions:** ['listenPassage'] · **Chips:** ['Let me try bars 6-7 slowly', 'Play bars 6-9 for me', 'Show me the fingering']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_listen_then_try`

- **Question:** Play bars 1 and 2 for me first, then let me try them.
- **Reply:** "Lovely — I'll play bars 1-2 slowly for you first, then it's your turn note-by-note. Listen for E-D-C-D, then E-E-E held longer. Keep fingers 3-2-1-2-3 as shown."
- **Actions:** ['listenPassage', 'practicePassage'] · **Chips:** ['Play it again slower', 'Let me try bars 3-4 next', 'Play whole piece for me']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `ia_listen_then_try`

- **Question:** Play bars 1 and 2 for me first, then let me try them.
- **Reply:** "Lovely idea! I'll play bars 1-2 for you first so you can hear how they go, then it's your turn to try them note-by-note."
- **Actions:** ['listenPassage', 'practicePassage'] · **Chips:** ['Play it slower', 'Let me try left hand', 'Play bars 3-4 next']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Let me try left hand'

### `ia_listen_then_try`

- **Question:** Play bars 1 and 2 for me first, then let me try them.
- **Reply:** "Lovely idea! I'll play bars 1-2 for you first so you can hear the tune, then it's your turn to try them note-by-note. Listen for E-D-C-D, then E-E-E held long."
- **Actions:** ['listenPassage', 'practicePassage'] · **Chips:** ['Play it slower please', 'Let me try again', 'Play bars 3-4 for me']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `ia_scale_exercise`

- **Question:** Teach me the G major scale, one octave, right hand.
- **Reply:** "Lovely choice — G major is a perfect first sharp-key scale! I'll set up one octave for your right hand, note-by-note, so you can find the shape comfortably. Keep your wrist loose and tuck the thumb under smoothly on the way up."
- **Actions:** ['practiceExercise'] · **Chips:** ['Play it for me first', 'Go a bit slower', 'Try left hand too']
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Try left hand too'

### `ia_scale_exercise`

- **Question:** Teach me the G major scale, one octave, right hand.
- **Reply:** "Lovely choice — G major is a great first sharp-key scale! I'll open a one-octave right-hand exercise for you to try note-by-note. Follow the fingering on screen and keep your wrist loose."
- **Actions:** ['practiceExercise'] · **Chips:** ['Play it again a bit faster', 'Try it with the left hand', 'Try two octaves']
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Try it with the left hand'
- Judge, unsupported: ['Follow the fingering on screen — the context never says the scale exercise displays fingering.']

### `ia_terminal_last`

- **Question:** Let me hear bars 1 to 2, then start a lesson on this piece.
- **Reply:** "Lovely choice! I'll play bars 1-2 for you now so you can hear that opening, then we'll dive straight into a lesson on this piece together."
- **Actions:** ['listenPassage', 'startLesson'] · **Chips:** ['Practice bars 1-2 slowly', 'Play the whole piece for me', 'Show me the fingering']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_terminal_last`

- **Question:** Let me hear bars 1 to 2, then start a lesson on this piece.
- **Reply:** "Lovely choice! I'll play bars 1-2 for you now so you can hear that E-D-C-D, E-E-E tune, then we'll start your lesson on it together."
- **Actions:** ['listenPassage', 'startLesson'] · **Chips:** ['Play it again slower', 'Let me try bars 1-2 now', 'Show me the fingering']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_terminal_last`

- **Question:** Let me hear bars 1 to 2, then start a lesson on this piece.
- **Reply:** "Lovely choice! I'll play bars 1-2 for you now so you can hear how it goes, then we'll dive straight into a lesson on it together."
- **Actions:** ['listenPassage', 'startLesson'] · **Chips:** ['Practice bars 1-2 slowly', 'Show me the fingering', 'Play the whole piece for me']
- ❌ grounding.hand_tracks: listenPassage hand R but the piece has one track

### `ia_grown_up`

- **Question:** A grown-up asks: For grown-ups: how is it going? Answer the grown-up in plain adult language from Progress, Practice history and This piece over time: time practised, what's going well, where the chil
- **Reply:** "This week she's done 42 minutes over 3 days, after 65 minutes over 4 days last week – a nice steady routine. On Mary Had a Little Lamb she's improved from 61% to 92% correct, with her last three tries better than before, getting almost all the notes in time. She's still getting stuck in bar 4, playing F instead of G four times out of six. One tip: ask her to play just bar 4 very slowly and find the G with finger 5 before she plays the whole piece."
- **Actions:** [] · **Chips:** []
- ❌ adherence.no_numbers: quotes grader numbers unasked: ['61%', '92%']
- Judge, unsupported: ["Refers to the child as 'she'; the context never gives the child's gender.", "'playing F instead of G four times out of six' is more precise than the context. It says bar 4 was wrong in 4 of 6 takes, usually G4 played as F4, not that F was played in all four.", "'a nice steady routine' glosses over a real drop from 65 min on 4 days to 42 min on 3 days."]

### `ia_grown_up`

- **Question:** A grown-up asks: For grown-ups: how is it going? Answer the grown-up in plain adult language from Progress, Practice history and This piece over time: time practised, what's going well, where the chil
- **Reply:** "This week she's practised 42 minutes over 3 days, down a little from 65 minutes over 4 days last week. It's going really well — Mary Had a Little Lamb has improved from 61% to 92% over 6 takes, and she now gets almost all the notes in time. She's stuck on bar 4, where the G often comes out as F. One tip: have her play bars 3-4 very slowly and name the G aloud before she plays it."
- **Actions:** [] · **Chips:** []
- ❌ adherence.no_numbers: quotes grader numbers unasked: ['61%', '92%']
- Judge, unsupported: ['"she" / "her": the context never states the child\'s gender, only \'Child learner, age 7\'.']

### `gr_missing_bar`

- **Question:** How should I finger bar 12?
- **Reply:** "Good question — this version of Mary Had a Little Lamb only has 8 bars, so there's no bar 12 to finger! Which bar from 1-8 did you mean? I'm happy to walk through the fingering with you."
- **Actions:** [] · **Chips:** ['How should I finger bar 4?', 'Play bars 1-2 for me', 'Let me practice bars 1-4']
- ❌ followups.echo: repeats the question just asked: 'How should I finger bar 4?'

### `gr_timing_unassessed`

- **Question:** Was my rhythm OK on that take?
- **Reply:** "Good try! On that take timing wasn't tracked, so I can't tell if your rhythm was steady or not. Note-wise you got almost all of them — just played E instead of D on beat 2 in bar 1. Want to try it in timed mode so I can really hear your rhythm?"
- **Actions:** [] · **Chips:** ["Yes, let's try in time", 'Play it for me first', 'Practice bar 1 slowly']
- ❌ grounding.timing_unassessed: judges timing ('rhythm was') but timing wasn't assessed
- Judge, unsupported: ['"try it in timed mode" — the context shows only "Mode: wait"; no app guide confirms a mode called "timed", though one is plausible.']

### `gr_timing_unassessed`

- **Question:** Was my rhythm OK on that take?
- **Reply:** 'Nice playing — and good question! That take was note-by-note, so timing wasn’t assessed and I can’t tell how your rhythm was from it.\n\nIf you’d like to check rhythm, let’s do a timed run with a count-in and keep counting aloud together.'
- **Actions:** [] · **Chips:** ["Let's do a timed run", 'Play it for me first', 'Slower, left hand only']
- ❌ followups.infeasible: left-hand chip on a one-track piece: 'Slower, left hand only'

### `gr_goal_no_date`

- **Question:** My goal is to play this hands together at full speed by next Friday.
- **Reply:** "Lovely goal — I'll save that for you. Quick note: this version of Mary Had a Little Lamb is right-hand only, so there's no left-hand part to add for hands-together. Let's aim for smooth and steady at full speed by next Friday instead. Want to start with bars 1-4 slowly to build confidence?"
- **Actions:** ['setGoal'] · **Chips:** ["Yes, let's practice bars 1-4", 'Make a practice plan for this week', 'Play it for me first']
- ❌ task.action_field: action 0 goalDate: expected None, got '2026-11-13'
- ❌ grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from
- Judge, unsupported: ['goalDate "2026-11-13" in the setGoal action: the context has no current date, so \'next Friday\' cannot be resolved to a specific date']

### `gr_goal_no_date`

- **Question:** My goal is to play this hands together at full speed by next Friday.
- **Reply:** "Lovely goal to aim for! Just so you know, this version of Mary Had a Little Lamb is right-hand only, so there's no left hand to add in. I've saved your goal to play it smoothly at full speed by next Friday, and we can build up to it step by step starting nice and steady."
- **Actions:** ['setGoal'] · **Chips:** ["Let's practice bars 1-4", 'Make a practice plan for this', 'Play it for me first']
- ❌ task.action_field: action 0 goalDate: expected None, got '2026-11-13'
- ❌ adherence.claims_done: says it already acted: "I've saved"
- ❌ grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from
- Judge, unsupported: ['goalDate "2026-11-13" in the setGoal action (no today\'s date in context, so next Friday\'s date can\'t be known)', 'Saved goal text still says "hands together" even though the reply tells the learner there\'s no left hand']

### `gr_goal_no_date`

- **Question:** My goal is to play this hands together at full speed by next Friday.
- **Reply:** "Lovely goal — I've saved it for next Friday! This version of Mary Had a Little Lamb is right-hand only, so we'll get it smooth and steady at full speed, then we can add a left hand if you like. Shall we start with bars 1-4 note-by-note to build it up?"
- **Actions:** ['setGoal'] · **Chips:** ["Yes, let's practise bars 1-4", 'Play it for me first', 'Make a practice plan for this week']
- ❌ task.action_field: action 0 goalDate: expected None, got '2026-11-13'
- ❌ adherence.claims_done: says it already acted: "I've saved"
- ❌ grounding.invented_date: goalDate 2026-11-13 but the context has no today's date to count from
- Judge, unsupported: ['goalDate "2026-11-13" in the setGoal action: the context gives no current date, so next Friday\'s date can\'t be known', '"I\'ve saved it for next Friday!" (implies a resolved date that was invented)', '"then we can add a left hand if you like": there are no separate hand tracks and nothing in the context says the app can add a left hand']

### `gr_goal_with_date`

- **Question:** My goal is to play this at full speed by next Friday.
- **Reply:** "Lovely goal — I've saved it for next Friday! Since it's all right-hand in C position, let's get bars 1-4 smooth first, then 5-8, then join them up at full speed. Want to start with bars 1-4 nice and steady today?"
- **Actions:** ['setGoal'] · **Chips:** ["Yes, let's practice bars 1-4", 'Make a practice plan for this week', 'Play it for me first']
- ❌ adherence.claims_done: says it already acted: "I've saved"

### `gr_goal_with_date`

- **Question:** My goal is to play this at full speed by next Friday.
- **Reply:** "That's a lovely goal — I've saved it for next Friday so we can work toward it together. Since Mary Had a Little Lamb is short and gentle, let's nail bars 1-4 first note-by-note, then build up to playing it all smoothly in time."
- **Actions:** ['setGoal'] · **Chips:** ["Let's start with bars 1-4", 'How should I practice this week?', 'Play it for me first']
- ❌ adherence.claims_done: says it already acted: "I've saved"

### `gr_goal_with_date`

- **Question:** My goal is to play this at full speed by next Friday.
- **Reply:** "Love it — let's get Mary Had a Little Lamb smooth at full speed by next Friday! I've saved that goal. Since you already read treble and play hands separately, we'll build up with short, steady takes. Want to start with bars 1-4 note-by-note to lock in the notes?"
- **Actions:** ['setGoal'] · **Chips:** ["Yes, let's practice bars 1-4", 'Make a practice plan for this week', 'Play it for me first']
- ❌ adherence.claims_done: says it already acted: "I've saved"

### `gr_not_ready`

- **Question:** Am I ready to play this at full speed now?
- **Reply:** "You're getting very close, but not quite for full speed yet. Bar 7 still catches you — that E on beat 3 often gets missed after the two Ds. I'll set bars 7-8 note-by-note so you can secure it, then we'll try it up to speed."
- **Actions:** ['practicePassage'] · **Chips:** ['Yes, let me try bars 7-8', 'Play bar 7 for me first', 'How should I finger bar 7?']
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track

### `co_auto_event`

- **Question:** Tell me how that attempt went, like my piano teacher, and guide me into the selected exercise.
- **Reply:** "Lovely singing tone — you got almost all the notes and your rhythm was nice and even! The slip was bar 4 beat 2 where an F crept in for the G, and one E went missing in bar 7. I'll set up bars 4-7 nice and slow note-by-note so you can nail that jump to G, then it's your turn."
- **Actions:** ['practicePassage'] · **Chips:** ['Play it for me first', 'Let me try the whole piece', 'A bit slower please']
- ❌ task.action_field: action 0 toBar: expected '4–5', got 7
- ❌ grounding.hand_tracks: practicePassage hand R but the piece has one track
- Judge, unsupported: ['"Lovely singing tone" — the grader evidence says nothing about tone quality.']

### `co_auto_event`

- **Question:** Tell me how that attempt went, like my piano teacher, and guide me into the selected exercise.
- **Reply:** "Lovely careful run — you got almost all the notes. Just the G in bar 4 turned into an F, and the E in bar 7 didn't quite sound. Your rhythm was nice and even. Let's run bars 1-8 again with those two spots in mind — I'll set it up for you to try now."
- **Actions:** ['practicePassage'] · **Chips:** ['Play it for me first', 'Can we go slower?', 'Just bars 4 and 7 please']
- ❌ task.action_field: action 0 fromBar: expected '3–4', got 1
- ❌ task.action_field: action 0 toBar: expected '4–5', got 8

