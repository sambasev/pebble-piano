# Tutor live evaluation

Model `muse-spark-1.3`, 2026-11-03T23:41:23Z. The real app end to end: real pieces and graded takes, library, lessons, memory and action checks; only the model is live.

**20 of 20 passed.** Regenerate: `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`.

| Scenario | Case | Result | Seconds | What happened |
|---|---|---|---|---|
| A | `a1_count_rhythm` | ✅ | 7.0 | Explains the rhythm of a real bar from the score data and offers follow-ups |
| A | `a2_tap_follow_up` | ✅ | 12.4 | A tapped follow-up chip is answered in the same conversation |
| B | `b1_listen_then_try` | ✅ | 11.6 | “Play it, then let me try” runs a demonstration and queues the practice |
| B | `b2_recurring_mistakes` | ✅ | 19.2 | After three real takes with the same slip, names the bar |
| B | `b3_not_ready_from_wait_mode` | ✅ | 20.7 | Doesn't call the piece ready from note-by-note takes |
| B | `b4_plan_session` | ✅ | 14.9 | Plans a 15-minute session as a saved checklist |
| C | `c1_search_then_open` | ✅ | 12.6 | Searches the real library, then opens and downloads the first result |
| D | `d1_scale_exercise` | ✅ | 7.7 | “Teach me G major” opens a generated, graded scale exercise |
| D | `d2_play_chord` | ✅ | 6.2 | Demonstrates a chord with playNotes |
| D | `d3_ear_training` | ✅ | 9.1 | Opens ear training for hearing major vs minor |
| E | `e1_last_time` | ✅ | 22.3 | Remembers the previous conversation through its own notes |
| E | `e2_weekly_progress` | ✅ | 14.2 | Answers “how did I do this week” from real practice sessions |
| E | `e3_dated_goal` | ✅ | 10.0 | Saves a goal with its target date |
| F | `f1_cant_hear_me` | ✅ | 7.8 | After a take where few notes were heard, points at the input or calibration |
| F | `f2_change_teacher` | ✅ | 5.0 | Finds the teacher setting from the app guide |
| F | `f3_switch_input_waits` | ✅ | 6.5 | Offers to switch input and changes nothing until tapped |
| F | `f4_played_it_right` | ✅ | 13.7 | Keeps a disputed take (the bar the grader flagged) for checking, without regrading |
| G | `g1_child_what_note` | ✅ | 5.7 | Child in a real Learn lesson: names the next note simply |
| G | `g2_child_slower` | ✅ | 5.8 | Child: “Make it slower” slows the exercise |
| G | `g3_grown_up` | ✅ | 15.7 | Grown-up: answers in adult language from the child's real progress |

## Transcripts

### a1_count_rhythm

- learner: How do I count the rhythm in bar 4?
- tutor: Good looking at the score — bar 4 is a rest bar.  In this piece it's a whole-bar rest in 4/4, so you count just like you play:  **1 - 2 - 3 - 4** silently, no keys down.  Try tapping your knee or nodding on each number to keep the pulse, then come in on bar 6 with E E F G.  Bars 1-5 are all the same — 5 bars of waiting before the tune starts.

### a2_tap_follow_up

- learner: What notes are in bar 1?
- tutor: Good checking! Bar 1 has no notes to play — it's a whole-bar rest.  In this 4/4 piece that means 4 beats of silence: count 1-2-3-4 quietly and don't play.  Bars 1-5 are all rests like that. The tune itself starts in bar 6 with E - E - F - G.
- learner: Where does the tune start?
- tutor: The tune starts in bar 6, after five bars of rest.  Count 1-2-3-4 through those silent bars, then play in bar 6: E - E - F - G, and bar 7: G - F - E - D.

### b1_listen_then_try

- learner: Play bars 1 to 2 for me first, then let me try them.
- tutor: Got it! I'll play bars 1-2 first, then it's your turn.  Quick heads-up: in this piece those 2 bars are whole-bar rests - so you'll hear 8 beats of counting with no notes. Great for feeling the pulse before the tune starts in bar 6.
- app: Started bars 1–2, all its notes (the file has one track), 100%, demonstration. Play when you're ready; I'll review the graded take.

### b2_recurring_mistakes

- learner: Where do I keep making mistakes?
- tutor: Great spot to check — you're very consistent at 99%!  All 3 recent takes have the same slip:  * **Printed bar 7** — beat 2, an extra F#4 sneaks in between the F and E. That's the G - F - E - D bar.  The other pink flags in the picture — bars 9 and 13 — are just long pauses in note-by-note mode, not wrong notes. You got all 62/62 notes right.  That extra in bar 7 is likely a brush of the black key next door. Want to loop just that bar to clean it?

### b3_not_ready_from_wait_mode

- learner: I've played it perfectly three times now. Am I ready to play it at full speed?
- tutor: Great playing - 62/62 notes correct three times in a row! That's a real win.  Not quite ready to call it full-speed yet, though. Those three takes were in wait-for-note mode, which waits for you and doesn't check timing.  The grader shows the rhythm still needs work, even with perfect notes: - bars 9 and 13, beat 3 - the D and C after the dotted note came in ~100% late - bars 15-16 - the short E-F pickups were late - bar 18, beat 1 - came in ~50% early  Those are all the dotted and short-long rhythms. Let's prove it with one timed take with count-in. Want to try it slower first?

### b4_plan_session

- learner: Make me a 15 minute practice plan for today.
- tutor: Great playing — 62/62 notes right! For today let's turn that wait-mode accuracy into steady rhythm.  I've saved you a 15-min plan: 1. Warm-up 2 min 2. Bar 7 clean - you added an extra F# last time 3. Bars 9 & 13 dotted rhythms - count 1-2-3-+ 4. Play-through 6-13 slow in time  We'll start now with bars 7-9 at 50% in time. Press Start practice when ready, and count aloud.
- app: Saved today's plan: 4 steps, 15 minutes. Tick them off in the chat.
- app: Prepared bars 7–9, all its notes (the file has one track), 50%, in time. Press Start practice when you're ready.

### c1_search_then_open

- learner: Find me an easy Bach piece in the library.
- tutor: Of course! I'm searching the library now for an easy Bach piece at your level. We'll see up to 5 results in a moment.
- app: Library search by Bach, Elementary, top 3: #1 [catalog:mutopia-76] Menuet, BWV Anh. 115 — J. S. Bach (attributed) · Elementary · Music Library #2 [catalog:mutopia-79] Musette, BWV Anh. 126 — J. S. Bach (attributed) · Elementary · Music Library #3 [catalog:mutopia-1016] Polonaise in G minor, BWV Anh. 119 — J. S. Bach (attributed) · Elementary · Music Library
- learner: Open the first one.
- tutor: Great choice — opening the Menuet, BWV Anh. 115 for you now.
- app: Opening Menuet, BWV Anh. 115 by J. S. Bach (attributed) from the Music Library…
- app: Opened Menuet, BWV Anh. 115 in Practice.

### d1_scale_exercise

- learner: Teach me the G major scale with my right hand, one octave.
- tutor: Great choice — G major is perfect with your Ode to Joy right hand work. I've set up a 1-octave G major scale for your right hand, nice and slow in note-by-note mode.  Just follow the keys and finger numbers on screen up and back down. Take your time, curve your fingers, and keep a steady thumb tuck under. Tap Start practice, then play your first note when you're ready.
- app: Started G major scale, 1 octave, right hand, 50%, note by note. Play when you're ready; I'll review the graded take.

### d2_play_chord

- learner: What does a C major chord sound like? Play it for me.
- tutor: Great question! A C major chord is made of C - E - G together, and it sounds bright and happy. Listen now — I'm lighting up the keys for you.
- app: Playing C4+E4+G4 at 80 BPM; watch the keys light up.

### d3_ear_training

- learner: I can't hear the difference between major and minor. Can you quiz me?
- tutor: Great ear to train! Quick tip: major sounds bright and happy, like your Ode to Joy, minor sounds darker and sad — only one note is different, the 3rd.  Let's quiz you — I'll play examples and you tell me major or minor. Starting ear training now:
- app: Opened ear training: Level 1 · Three notes. Open Tutor in the header to keep chatting.

### e1_last_time

- learner: What did we work on last time?
- tutor: Last time we were on this same piece — Ode to Joy beginner version for right hand.  You asked for help with the left hand in bar 4 because it felt slow.  In this arrangement on screen now, bars 1-5 are rests and the tune starts in bar 6 with E - E - F - G, all right hand, so there's no left-hand part to play here. Want to pick up where you left off and work on that opening tune together?

### e2_weekly_progress

- learner: How much have I practised this week?
- tutor: This week is logged as 0 min on 0 days — and last week was the same.  I can see 2 graded takes of Ode to Joy just now at 99-100% for notes, so you have been playing, but that time hasn't been counted into your weekly minutes.  Want to set a small goal so we can start tracking it?

### e3_dated_goal

- learner: My goal is to play Ode to Joy smoothly at full speed by 2026-12-18.
- tutor: Great goal — I've saved it: play Ode to Joy smoothly at full speed by 2026-12-18.  You've got the perfect starter piece open - right hand only in C major. A good path: 1. Learn bars 6-7 note-by-note in wait mode 2. Add bars 11-13, then 17-19 3. Join them smoothly at a slower tempo, then build to 100%.  No graded takes yet, so press Start practice when you're ready and I'll coach you from the grading. Want to start with the famous opening?
- app: Goal saved: play Ode to Joy smoothly at full speed, by Dec 18, 2026.

### f1_cant_hear_me

- learner: It doesn't seem to hear most of what I play.
- tutor: You're right — I only heard 3 of 62 notes in that take, so it's an input issue, not your playing.  Right now no input is chosen: microphone is off and no Bluetooth MIDI piano is connected.  Tap the input pill in the header and choose microphone or Bluetooth MIDI. If you use microphone, please Calibrate once — stay quiet, then play C4, D4, E4. I've added an Input settings button below to open that.  Then try bars 6-8 note-by-note again.
- app: Offered: Open input settings. Nothing changes until you press the button.

### f2_change_teacher

- learner: How do I change my teacher to Kriti?
- tutor: Easy! Go to the Learn tab to see your unit map, then use the Teacher menu there to switch from Alex to Kriti.  Kriti is our stricter teacher, Alex is more relaxed - you can switch back anytime the same way.

### f3_switch_input_waits

- learner: Switch me to the computer keyboard please.
- tutor: Switching you to computer keyboard now — tap that button to confirm. Once it's selected you can play Ode to Joy with your computer keys, starting on E in bar 6.
- app: Offered: Use the computer keyboard. Nothing changes until you press the button.

### f4_played_it_right

- learner: Bar 6 was marked wrong but I'm sure I played it right.
- tutor: You did play bar 6 right - E E F G, all 4 correct, 0 missed.  What the grader heard was one *extra* F in beat 2 of bar 6. That's usually a double-touch or brushing the key twice, not a wrong pitch. That's why it's still 62/62 and 99% - a pass.  I've saved this take so we can check the grader. It doesn't change your grade, but it helps us spot if it keeps happening. If you want, replay just bar 6 slowly and lift cleanly off each E before the F.
- app: Saved your latest take of Ode to Joy (Beethoven, Symphony No. 9) - beginner, C major, right hand for checking the grader. Your grade is unchanged.

### g1_child_what_note

- learner: What's this note?
- tutor: Hmm, I don't see a note right now! Let's open Meet Middle C to play together. Tap start when you are ready!

### g2_child_slower

- learner: Make it slower
- tutor: Good idea! Let's make it nice and slow. Now let's play together!
- app: Set this passage to 85% speed. Your take has not been graded.

### g3_grown_up

- learner: For grown-ups: how is it going?
- tutor: Here's how it's going on Ode to Joy beginner:  Time practised: the tracker shows 0 min this week / last week, but there are 2 graded takes just now — so playing is happening, just not logged as minutes.  What's going well: note accuracy is excellent. 62/62 notes correct in both takes, passed both times, 100% then 99% — just 1 extra note the second time.  Where stuck: rhythm, not notes. Dotted patterns are consistently late — bar 9 beat 3, bar 13 beat 3, bars 15-16 beats 2.5-3, and bar 21. Both takes were done note-by-note in wait mode, so we haven't yet seen steady playing in time at the 100 BPM target.  One tip: keep note-finding as is, and next do a short timed run at a slow speed on bars 9 and 13 only to lock in those dotted rhythms.
