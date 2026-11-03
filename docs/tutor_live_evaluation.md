# Tutor live evaluation

Model `muse-spark-1.3`, 2026-11-03T23:46:54Z. The real app end to end: real pieces and graded takes, library, lessons, memory and action checks; only the model is live.

**20 of 20 passed.** Regenerate: `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`.

| Scenario | Case | Result | Seconds | What happened |
|---|---|---|---|---|
| A | `a1_count_rhythm` | ✅ | 10.0 | Explains the rhythm of a real bar, streamed as it arrives, and offers follow-ups |
| A | `a2_tap_follow_up` | ✅ | 12.8 | A tapped follow-up chip is answered in the same conversation |
| B | `b1_listen_then_try` | ✅ | 16.6 | “Play it, then let me try” runs a demonstration and queues the practice |
| B | `b2_recurring_mistakes` | ✅ | 18.7 | After three real takes with the same slip, names the bar |
| B | `b3_not_ready_from_wait_mode` | ✅ | 23.8 | Doesn't call the piece ready from note-by-note takes |
| B | `b4_plan_session` | ✅ | 15.3 | Plans a 15-minute session as a saved checklist |
| C | `c1_search_then_open` | ✅ | 12.9 | Searches the real library, then opens and downloads the first result |
| D | `d1_scale_exercise` | ✅ | 6.0 | “Teach me G major” opens a generated, graded scale exercise |
| D | `d2_play_chord` | ✅ | 7.3 | Demonstrates a chord with playNotes |
| D | `d3_ear_training` | ✅ | 6.5 | Opens ear training for hearing major vs minor |
| E | `e1_last_time` | ✅ | 19.3 | Remembers the previous conversation through its own notes |
| E | `e2_weekly_progress` | ✅ | 12.6 | Answers “how did I do this week” from real practice sessions |
| E | `e3_dated_goal` | ✅ | 8.0 | Saves a goal with its target date |
| F | `f1_cant_hear_me` | ✅ | 8.9 | After a take where few notes were heard, points at the input or calibration |
| F | `f2_change_teacher` | ✅ | 3.4 | Finds the teacher setting from the app guide |
| F | `f3_switch_input_waits` | ✅ | 5.7 | Offers to switch input and changes nothing until tapped |
| F | `f4_played_it_right` | ✅ | 14.9 | Keeps a disputed take (the bar the grader flagged) for checking, without regrading |
| G | `g1_child_what_note` | ✅ | 10.8 | Child in a real Learn lesson: names the next note simply |
| G | `g2_child_slower` | ✅ | 4.4 | Child: “Make it slower” slows the exercise |
| G | `g3_grown_up` | ✅ | 16.4 | Grown-up: answers in adult language from the child's real progress |

## Transcripts

### a1_count_rhythm

- learner: How do I count the rhythm in bar 4?
- tutor: Bar 4 is a rest bar - you don't play anything, you just count it.  In 4/4, count steady: 1 - 2 - 3 - 4.  Try tapping your knee on each number while the playhead moves across that bar. That keeps you in time so you come in right on the E's in bar 6.
- app: Highlighted bar 4.

### a2_tap_follow_up

- learner: What notes are in bar 1?
- tutor: Bar 1 has no notes to play — it's a whole-bar rest.  In 4/4 that means rest and count 4 beats: 1-2-3-4, then go on to bar 2.  The tune starts later in bar 6 with E E F G.
- learner: What notes are in bar 6?
- tutor: Bar 6 is where the tune starts — E E F G, all quarter notes: 1-2-3-4.
- app: Highlighted E4 F4 G4.

### b1_listen_then_try

- learner: Play bars 1 to 2 for me first, then let me try them.
- tutor: Got it! Quick heads-up: bars 1-2 in this sheet are full-bar rests, so you'll hear silence for the demo.  I'll play them first, then it will be your turn to try - just wait through the 4 beats in each bar in wait mode.
- app: Started bars 1–2, both hands, 100%, demonstration. Play when you're ready; I'll review the graded take.

### b2_recurring_mistakes

- learner: Where do I keep making mistakes?
- tutor: Great news - you're getting 62/62 notes right for 99%!  Your one repeat slip is in bar 7, in all 3 recent takes:  Bar 7 beat 2: you add an extra F#4 between the G and F. The printed notes are just G - F - E - D.  The other "late" marks in bars 9, 13, 15, 16 and 21 are just pauses in note-by-note mode, not wrong notes.  Want to clean up that bar 7 extra note together?

### b3_not_ready_from_wait_mode

- learner: I've played it perfectly three times now. Am I ready to play it at full speed?
- tutor: Great work getting 100% of the notes 3 times — that part is perfect!  Those 3 takes were in wait mode, where the piano waits for you note-by-note, so rhythm and speed aren’t tested yet. That’s why it says 1100+ BPM.  To be ready for full speed you need a passed take in timed mode, in time.  Let’s try it timed together — I’ve set bars 8-10 at 50% to learn the count. Press Start practice when you’re ready.
- app: Prepared bars 8–10, all its notes (the file has one track), 50%, in time. Press Start practice when you're ready.

### b4_plan_session

- learner: Make me a 15 minute practice plan for today.
- tutor: Great 99% run on Ode to Joy! Let's use it for today's 15 minutes - I've saved this plan for you:  1. Warm-up 2 min: C-D-E-F-G right hand 2. Clean 4 min: bars 7-9 - you added an extra F# in bar 7 3. Smooth 4 min: bars 15-16 - those E-F eighths had big pauses 4. Run 3 min: full piece 5. Learn 2 min: Meet Middle C  We're starting you on step 2 in note-by-note mode so you can focus on no extra notes. Press Start practice when ready!
- app: Saved today's plan: 5 steps, 15 minutes. Tick them off in the chat.
- app: Started bars 7–9, all its notes (the file has one track), 50%, note by note. Play when you're ready; I'll review the graded take.

### c1_search_then_open

- learner: Find me an easy Bach piece in the library.
- tutor: Got it — let me find an easy Bach piece for you in the library.
- app: Library search by Bach, Elementary, top 3: #1 [catalog:mutopia-76] Menuet, BWV Anh. 115 — J. S. Bach (attributed) · Elementary · Music Library #2 [catalog:mutopia-79] Musette, BWV Anh. 126 — J. S. Bach (attributed) · Elementary · Music Library #3 [catalog:mutopia-1016] Polonaise in G minor, BWV Anh. 119 — J. S. Bach (attributed) · Elementary · Music Library
- learner: Open the first one.
- tutor: Opening that Menuet in G major for you now — a lovely easy Bach piece to try next.
- app: Opening Menuet, BWV Anh. 115 by J. S. Bach (attributed) from the Music Library…
- app: Opened Menuet, BWV Anh. 115 in Practice.

### d1_scale_exercise

- learner: Teach me the G major scale with my right hand, one octave.
- tutor: Great choice! G major has one sharp - F#. I've set it up for your right hand, one octave, in wait-mode so it waits for each correct note.  Watch for the app's suggested fingering, keep your wrist loose, and tuck your thumb under smoothly going up. Let's try it!
- app: Started G major scale, 1 octave, right hand, 50%, note by note. Play when you're ready; I'll review the graded take.

### d2_play_chord

- learner: What does a C major chord sound like? Play it for me.
- tutor: Great question! A C major chord is C - E - G together. It sounds bright and happy - it's the home chord of your Ode to Joy in C major. I'll play it for you now - listen to how all three notes ring together.
- app: Playing C4+E4+G4 at 80 BPM; watch the keys light up.

### d3_ear_training

- learner: I can't hear the difference between major and minor. Can you quiz me?
- tutor: Yes - that's a perfect thing to train! I've opened the ear training quiz for you starting at level 1 where you'll hear major vs minor.  Listen for: major sounds bright and happy like your Ode to Joy, minor sounds darker and sadder. Have a go and tell me how it goes!
- app: Opened ear training: Level 1 · Three notes. Open Tutor in the header to keep chatting.

### e1_last_time

- learner: What did we work on last time?
- tutor: Good memory check! My notes from last time say you asked for help with the left hand in bar 4 because it felt slow, on this same Ode to Joy.  Just to pick up carefully: the version open now is right-hand only, and bars 1-5 are rests — the tune starts in bar 6 with E E F G. We don't have any graded takes saved yet, so we didn't get a recording of it.  Want to pick that up again today starting with bars 6-7?

### e2_weekly_progress

- learner: How much have I practised this week?
- tutor: Nothing logged yet this week — 0 min on 0 days, same as last week.  But you've just played 2 graded takes of Ode to Joy at 99-100% notes correct, so you're already making a start! Want to make a plan to get some regular minutes in?

### e3_dated_goal

- learner: My goal is to play Ode to Joy smoothly at full speed by 2026-12-18.
- tutor: Lovely goal — I've saved it: play Ode to Joy smoothly at full speed by 2026-12-18.  You've got about 6 weeks, which is plenty for this beginner right-hand version. The tune starts in bar 6 with E E F G.  How about this: Weeks 1-2: bars 6-7 smooth note-by-note Weeks 3-4: add bars 11-13 Weeks 5-6: full passage at full speed, in time  Want to start with the first phrase together now?
- app: Goal saved: play Ode to Joy smoothly at full speed, by Dec 18, 2026.

### f1_cant_hear_me

- learner: It doesn't seem to hear most of what I play.
- tutor: You're right — it only heard 3 of 62 notes, so it's not you, it's the listening setup.  Right now no input is chosen, the microphone is off, and no Bluetooth piano is connected. That's why most notes show as missed.  Let's fix it: 1. Tap the input pill in the header and pick microphone or Bluetooth MIDI piano. Only Bluetooth MIDI is listened to — USB is ignored. 2. If you use microphone, calibrate once: stay quiet, then play C4, D4, E4. You'll find it in Practice > ⋯ menu > Calibrate piano (mic).  I've added an Open Input Settings button below — tap it to choose.
- app: Offered: Open input settings. Nothing changes until you press the button.

### f2_change_teacher

- learner: How do I change my teacher to Kriti?
- tutor: You can switch anytime! Go to Learn, then look at the unit map for the Teacher menu. Open it and choose Kriti - she's the strict teacher, while Alex is relaxed.  Let me know if you don't see the menu and we'll find it together.

### f3_switch_input_waits

- learner: Switch me to the computer keyboard please.
- tutor: Of course! I've put up the button to switch to computer keyboard — just tap it to confirm, then you can play Ode to Joy with your computer keys.
- app: Offered: Use the computer keyboard. Nothing changes until you press the button.

### f4_played_it_right

- learner: Bar 6 was marked wrong but I'm sure I played it right.
- tutor: You did get all the right notes in bar 6 — E E F G — and you passed 99% with 62/62 correct!  What the grader heard was 1 *extra* note: an extra F4 around beat 2 of bar 6. In wait mode that’s often a finger brushing the next key, a key re-sounding, or the mic picking up one note twice.  I’ve saved this take so we can check the grader. If you want, replay just bar 6 slowly and lift cleanly between the two E’s before moving to F.
- app: Saved your latest take of Ode to Joy (Beethoven, Symphony No. 9) - beginner, C major, right hand for checking the grader. Your grade is unchanged.

### g1_child_what_note

- learner: What's this note?
- tutor: I do not see a note waiting right now! Let's open Meet Middle C and meet our first note together!

### g2_child_slower

- learner: Make it slower
- tutor: Okay! Slower is good. Let's play soft and cozy together.
- app: Set this passage to 85% speed. Your take has not been graded.

### g3_grown_up

- learner: For grown-ups: how is it going?
- tutor: Here's how it's going on Ode to Joy beginner:  Time practised: no practice minutes logged this week or last, but I see 2 recent graded takes.  What's going well: note accuracy is excellent — 62/62 correct for 100% then 99%. They passed both takes.  Where they're stuck: rhythm, not notes. The dotted rhythms in bars 9, 13, 15, 16 and 21 are consistently late, bar 18 beat 1 is early, and the last take had one extra note in bar 6. They are playing note-by-note, not yet in time at the target 100 BPM.  One tip: keep note-by-note for learning the tune, then try one slow play-along run with the metronome to work on those long-short dotted patterns.
