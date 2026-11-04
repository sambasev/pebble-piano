# Tutor live evaluation

Model `muse-spark-1.3`, 2026-11-04T02:08:27Z. The real app end to end: real pieces and graded takes, library, lessons, memory and action checks; only the model is live.

**22 of 22 passed.** Regenerate: `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`.

| Scenario | Case | Result | Seconds | What happened |
|---|---|---|---|---|
| A | `a1_count_rhythm` | ✅ | 9.3 | Explains the rhythm of a real bar, streamed as it arrives, and offers follow-ups |
| A | `a2_tap_follow_up` | ✅ | 9.6 | A tapped follow-up chip is answered in the same conversation |
| B | `b1_listen_then_try` | ✅ | 12.0 | “Play it, then let me try” runs a demonstration and queues the practice |
| B | `b5_refused_demo_is_honest` | ✅ | 9.1 | Asked for a demo mid-take: keeps the take and never claims it played |
| B | `b6_stray_note_demo` | ✅ | 8.6 | A stray note doesn't block the demo |
| B | `b2_recurring_mistakes` | ✅ | 26.2 | After three real takes with the same slip, names the bar |
| B | `b3_not_ready_from_wait_mode` | ✅ | 23.3 | Doesn't call the piece ready from note-by-note takes |
| B | `b4_plan_session` | ✅ | 16.6 | Plans a 15-minute session as a saved checklist |
| C | `c1_search_then_open` | ✅ | 11.0 | Searches the real library, then opens and downloads the first result |
| D | `d1_scale_exercise` | ✅ | 7.0 | “Teach me G major” opens a generated, graded scale exercise |
| D | `d2_play_chord` | ✅ | 7.3 | Demonstrates a chord with playNotes |
| D | `d3_ear_training` | ✅ | 7.9 | Opens ear training for hearing major vs minor |
| E | `e1_last_time` | ✅ | 17.2 | Remembers the previous conversation through its own notes |
| E | `e2_weekly_progress` | ✅ | 11.3 | Answers “how did I do this week” from real practice sessions |
| E | `e3_dated_goal` | ✅ | 5.6 | Saves a goal with its target date |
| F | `f1_cant_hear_me` | ✅ | 10.0 | After a take where few notes were heard, points at the input or calibration |
| F | `f2_change_teacher` | ✅ | 4.4 | Finds the teacher setting from the app guide |
| F | `f3_switch_input_waits` | ✅ | 4.8 | Offers to switch input and changes nothing until tapped |
| F | `f4_played_it_right` | ✅ | 14.5 | Keeps a disputed take (the bar the grader flagged) for checking, without regrading |
| G | `g1_child_what_note` | ✅ | 5.5 | Child in a real Learn lesson: names the next note simply |
| G | `g2_child_slower` | ✅ | 5.9 | Child: “Make it slower” slows the exercise |
| G | `g3_grown_up` | ✅ | 14.2 | Grown-up: answers in adult language from the child's real progress |

## Transcripts

### a1_count_rhythm

- learner: How do I count the rhythm in bar 4?
- tutor: Good spot checking! In this piece, bar 4 is a whole-bar rest — that thick line hanging from the line means rest for the whole bar.  In 4/4, just count silently: 1 - 2 - 3 - 4, with nothing to play.  Those first 5 bars are all the same — a quiet intro before your E E F G starts in bar 6.

### a2_tap_follow_up

- learner: What notes are in bar 1?
- tutor: Bar 1 has no notes — it's a whole-bar rest. That's the little black rectangle hanging from the line you see in the image.  You count 4 beats silently, then stay silent through bars 2-5 too. The tune starts in bar 6 on E E F G.
- learner: Where does the melody start?
- tutor: The melody starts in bar 6 — after 5 bars of rest.  It starts on E: E E F G in bar 6, then G F E D in bar 7.

### b1_listen_then_try

- learner: Play bars 1 to 2 for me first, then let me try them.
- tutor: Yes! I'll play bars 1-2 slowly, then it's your turn.  Quick heads-up from the score: bars 1-2 in this piece are full-bar rests, so you'll hear 4 beats of counting in each bar with no notes to play. Listen along, then you try counting them with me note-by-note.
- app: Started bars 1–2, all its notes (the file has one track), 100%, demonstration. Play when you're ready; I'll review the graded take.

### b5_refused_demo_is_honest

- learner: Play bar 3 slowly for me.
- tutor: Good looking at the music! Bar 3 in this piece is a whole-bar rest — that's the "-" you see in bar 3 of the picture — so there's nothing to play, just 4 beats of silence.  The tune starts in bar 6 with E E F G. I'll play that slowly for you to get started, then it's your turn?

### b6_stray_note_demo

- learner: Play bar 3 slowly for me.
- tutor: I'll play bar 3 slowly for you now.  Just so you know, bar 3 in this piece is a full-bar rest - so you'll hear counting but no notes. The tune starts in bar 6 with E E F G.
- app: Started bars 3–3, all its notes (the file has one track), 50%, demonstration. Play when you're ready; I'll review the graded take.

### b2_recurring_mistakes

- learner: Where do I keep making mistakes?
- tutor: I tried to highlight bar 7 for you, but it didn't show. Please finish the take or say stop so I can show it. That extra F# in bar 7 G-F-E-D is the one to watch — this piece needs only white keys.
- app: Name the bars or keys to show.

### b3_not_ready_from_wait_mode

- learner: I've played it perfectly three times now. Am I ready to play it at full speed?
- tutor: Bravo — 62/62 correct three times in a row, zero wrong notes! That's real progress.  Not quite ready for full speed yet, because those three were in wait mode — note-by-note. That checks notes, not timing. Your rhythm shows the dotted notes in bars 9, 13, 15-16 are coming in about 100% late, and bar 18 beat 1 is early.  I'll set bars 8-10 timed at 50% so we can test the bar 9 rhythm in time, then it's your turn to try.
- app: Prepared bars 8–10, all its notes (the file has one track), 50%, in time. Press Start practice when you're ready.

### b4_plan_session

- learner: Make me a 15 minute practice plan for today.
- tutor: Here's your 15-minute plan - saved above! Great 99% on notes last time.  We'll start note-by-note since rhythm in wait mode isn't timed yet. Focus one thing at a time:  1. Clean that extra F# in bar 7 2. Hold the dotted notes long in bars 9 and 13  I'll start you on bars 7-9 slow, then it's your turn. Press Start practice when ready!
- app: Saved today's plan: 4 steps, 15 minutes. Tick them off in the chat.
- app: Started bars 7–9, all its notes (the file has one track), 50%, note by note. Play when you're ready; I'll review the graded take.

### c1_search_then_open

- learner: Find me an easy Bach piece in the library.
- tutor: Great choice — Bach has some lovely easy pieces. I'll search the library for Elementary Bach for you now.
- app: Library search by Bach, Elementary, top 3: #1 [catalog:mutopia-76] Menuet, BWV Anh. 115 — J. S. Bach (attributed) · Elementary · Music Library #2 [catalog:mutopia-79] Musette, BWV Anh. 126 — J. S. Bach (attributed) · Elementary · Music Library #3 [catalog:mutopia-1016] Polonaise in G minor, BWV Anh. 119 — J. S. Bach (attributed) · Elementary · Music Library
- learner: Open the first one.
- tutor: Opening the Menuet, BWV Anh. 115 for you now — a perfect easy Bach starter.
- app: Opening Menuet, BWV Anh. 115 by J. S. Bach (attributed) from the Music Library…
- app: Opened Menuet, BWV Anh. 115 in Practice.

### d1_scale_exercise

- learner: Teach me the G major scale with my right hand, one octave.
- tutor: Great choice! G major is a lovely bright scale with just one sharp - F#. I'll set up a one-octave right-hand exercise for you in note-by-note mode, so you can take your time. Follow the highlighted keys and suggested fingering on screen, and keep your hand relaxed and curved.
- app: Started G major scale, 1 octave, right hand, 50%, note by note. Play when you're ready; I'll review the graded take.

### d2_play_chord

- learner: What does a C major chord sound like? Play it for me.
- tutor: Great question! A C major chord sounds bright and happy. It's the notes C-E-G played together. I'll play it for you now — listen closely.
- app: Playing C4+E4+G4 at 80 BPM; watch the keys light up.

### d3_ear_training

- learner: I can't hear the difference between major and minor. Can you quiz me?
- tutor: Great ear to train — major often sounds bright and happy, minor sounds darker and sad. I'll open an ear-training quiz for you now, starting easy with major vs minor. Listen a few times and trust your first feeling!
- app: Opened ear training: Level 1 · Three notes. Open Tutor in the header to keep chatting.

### e1_last_time

- learner: What did we work on last time?
- tutor: Last time on Nov 3 we were on this same Ode to Joy and you asked for help with the left hand in bar 4 feeling slow.  Right now the version open here is right-hand only, and bars 1-5 are rests — the tune starts in bar 6 with E E F G. Want to pick up where the notes start?

### e2_weekly_progress

- learner: How much have I practised this week?
- tutor: Not yet this week — 0 minutes on 0 days so far.  You've just played 2 lovely graded takes of Ode to Joy though, with 100% and 99% notes correct! Want to set a little goal together so we start logging time?

### e3_dated_goal

- learner: My goal is to play Ode to Joy smoothly at full speed by 2026-12-18.
- tutor: Love it — saved! Your goal is to play Ode to Joy smoothly at full speed by Dec 18.  We can get there with small steps: first bars 6-7 note-by-note, then adding bars 11-13, keeping it steady. Since you haven't learned finger numbers yet, we'll use 1-thumb to 5-pinky together as we go.  Want to start with the opening E E F G in wait mode?
- app: Goal saved: play Ode to Joy smoothly at full speed, by Dec 18, 2026.

### f1_cant_hear_me

- learner: It doesn't seem to hear most of what I play.
- tutor: You're right — it only heard 3 of 62 notes in that take, with 59 missed and no extras, so it's not you.  Right now no input is chosen: microphone is off and no Bluetooth MIDI piano is connected.  Tap the input pill in the header and choose: * Bluetooth MIDI piano if you have one - only Bluetooth MIDI is listened to * Microphone if you're using the acoustic piano * Computer keyboard to test  If you use microphone, please calibrate once from the Practice tab ⋯ menu > Calibrate piano (mic): stay quiet ~10 seconds, then play C4, D4, E4. Then I'll play a small passage slowly, then it's your turn to try.
- app: Offered: Open input settings. Nothing changes until you press the button.

### f2_change_teacher

- learner: How do I change my teacher to Kriti?
- tutor: You can switch anytime! Go to the Learn section and open the unit map - look for the Teacher menu at the top, then choose Kriti.  Kriti is our stricter teacher, while I'm Alex and a bit more relaxed. The teaching content stays the same, just the style changes.

### f3_switch_input_waits

- learner: Switch me to the computer keyboard please.
- tutor: Got it — I'll switch you to computer keyboard so you can play Ode to Joy without a piano.  Tap the button to confirm, then use your computer keys to play the E-F-G notes in bars 6-7.
- app: Offered: Use the computer keyboard. Nothing changes until you press the button.

### f4_played_it_right

- learner: Bar 6 was marked wrong but I'm sure I played it right.
- tutor: You're right to double-check — you did get all 62 notes right in bar 6 and the whole piece, 99% and a pass.  What the grader heard in bar 6, which is E - E - F - G, was one *extra* F between the two E's on beat 2. That's usually a quick double-touch or brushing the next key early, not a wrong note.  I'll save this take so we can check the grader, it won't change your grade. The "late / early" messages don't matter here because you're in note-by-note mode. Want to replay just bar 6 cleanly?
- app: Saved your latest take of Ode to Joy (Beethoven, Symphony No. 9) - beginner, C major, right hand for checking the grader. Your grade is unchanged.

### g1_child_what_note

- learner: What's this note?
- tutor: I don't see a note waiting right now! Let's start Meet Middle C together. Tap start and we will find your first note!

### g2_child_slower

- learner: Make it slower
- tutor: Good idea! Slow and cozy is nice. Let's try again!
- app: Set this passage to 85% speed. Your take has not been graded.

### g3_grown_up

- learner: For grown-ups: how is it going?
- tutor: Here's how it's going on Ode to Joy beginner, right hand:  Time practised: 0 minutes logged this week and last week, but 2 graded takes were just completed.  Going well: Note accuracy is excellent - 62/62 notes correct, passed with 100% then 99%. No single bar is consistently wrong.  Stuck: Rhythm on the dotted longer notes - bars 9, 13, 15, 16 and 21 were played late, which is normal in note-by-note mode. One extra note slipped in at bar 6 last time. Finger numbers, playing in time, and left hand are not started yet.  Tip: Do short timed practice at a slow speed with the metronome on to lock in those long dotted notes in bars 9 and 13.
