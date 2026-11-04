# Pebble Piano: demo video script

Meta Hackathon, Multimodal AI and Meta Model API track. About 3 minutes.

**How to read this:** say the plain text out loud. Lines in **[brackets]** are what you do on
screen, and they happen where they sit in the text. *(pause)* means stop talking and let the app
be heard. The spoken part is about 430 words, so it fits in 3 minutes at a relaxed pace with the
pauses.

Tutor replies change from run to run, so the script doesn't quote them. Read out the part that
matters, like the bar number, or just let the viewer read it.

---

## 1. Hook (0:00–0:20)

**[Camera on your hands at the piano, Mac beside it, Pebble Piano on Practice with Mic and Guide
on. Play the passage and hit one wrong note on purpose.]**

*(pause: let the wrong note ring)*

Oops. That was a wrong note.

**[Cut to the screen: the red circle on the staff, the status line "You played E4 · play D4".]**

And Pebble Piano caught it. It heard me through the Mac's microphone, on a real piano, and it
knows exactly which note: I played an E, and the book says D.

## 2. The problem (0:20–0:40)

**[Camera on the printed book on the music stand.]**

Most of learning piano happens alone. You've got a book, maybe a lesson once a week, and in
between nobody tells you which bar went wrong, why, or what to practise next. So you end up
practising your mistakes.

I wanted a teacher who listens. So I built one.

## 3. It listens and grades (0:40–1:15)

**[Screen. Press Space.]**

First, I can hear how the passage should sound.

*(pause: two or three seconds of playback, keys lighting purple)*

**[Play the passage cleanly this time. Green circles appear on the printed notes.]**

Now I play it. Every note I get right gets a green circle on the page, and the playhead waits
for me on each chord, so I can go at my own speed.

**[Let go of the keys. Auto-grade fires and the report appears.]**

When I finish, it grades the take: every note right, wrong, missed or extra, with its bar and
beat, plus my rhythm and tempo.

**[Quick cut: playing a few notes on the computer keyboard, A S D F.]**

It works with a MIDI keyboard, an acoustic piano through the mic, or even the computer
keyboard. The listening and grading are our own code, not AI. It's signal processing and score
alignment, running right on the Mac, so my piano audio never leaves the computer.

## 4. The tutor, on Muse Spark (1:15–1:55)

**[Open the chat panel. Type "What went wrong?" and send.]**

But a grade is only half of it. So I can just ask: what went wrong?

*(pause: let the answer stream in)*

The tutor runs on Meta's Muse Spark. It doesn't guess from the audio. It reasons from the
grader's measurements: this take, my last dozen takes on this piece, and the bars I keep
missing. So it can tell me it's **[read out the bar it names]**, and what my usual slip is.

**[Tap the "Play it for me" chip.]**

I can have it play the bar for me.

*(pause: let it play)*

**[Type "Loop bars 3 to 4, right hand, at 60% speed" and send.]**

Or set up a drill: those two bars, right hand, slowly.

It can also plan a practice session and remember my goals. And it's honest: if it can't do
something right now, say I'm in the middle of a take, it tells me, instead of pretending it did.

## 5. Your own book, read by Muse Wonder (1:55–2:30)

**[Go to Books and import the Beyer Op. 101 PDF page. Select the lines and start reading.]**

Here's the part I'm proudest of. It works with the book you already own. This is a page of
Beyer's piano method, printed in 1895.

**[Cut to the finished read.]**

Meta's Muse Wonder reads it line by line: the time signature, the barlines, the rhythms, both
hands. Vision models sometimes put a note one line off, so we check every pitch against where
the notehead actually sits on the staff. On our benchmark, that gets this old book to about 95%
of notes right, and modern printed music to 100%.

**[Play a few bars of the newly read piece. Green circles land on the printed notes.]**

And now this page is a piece I can play and get graded on, just like the built-in lessons.

## 6. Everything else (2:30–2:45)

**[Fast montage, a second or two each: the Learn lesson map, an ear training question, a sight
reading question answered by playing the key, child mode, the Music Library.]**

There's a full beginner path too: piano lessons, ear training, sight reading, a mode for kids,
and a library of thirty free classical pieces.

## 7. Close (2:45–3:00)

**[Back to the camera on your hands. Play the passage cleanly. The report says pass.]**

*(pause: let the last chord ring)*

Our own code measures how you played. Meta's models turn that into teaching.

**[End card: Pebble Piano, "A piano tutor that listens", the GitHub link, "Built with Muse Spark
and Muse Wonder".]**

This is Pebble Piano: a piano tutor that listens.

---

## Before you record

- [ ] Meta key saved in **⋯ → AI settings…**, and the connection check passes.
- [ ] Quiet room. Turn on **Mic** and stay silent for the first second while it measures the room.
- [ ] Optional: run **Calibrate piano (mic)…** on the piano you'll film.
- [ ] Rehearse sections 3 and 4 off camera. The tutor takes several seconds to reply and answers
      differently each time, so do a few takes and keep the best one. Speed up the waits in the edit.
- [ ] Import the section 5 book page beforehand, so you know which lines read well. Reading takes
      about a minute a line; record it once and cut the wait.
- [ ] Hide the Dock and notifications, and make the window large so the staff reads on a phone.
- [ ] Record the app's sound directly as well as through the room mic.

## Don't say these on camera

They'd be wrong about the app today:

- That SAM 3.1 or voice transcription is part of the app. The client supports them, but the app
  only uses them in the AI settings connection check.
- That Bluetooth MIDI has been tested. It hasn't (see *Known issues* in the README).
- That the mic works in a noisy room. It misses many soft notes there.
- That there's an iPad or iPhone app. It's Mac only.

The older `docs/video_demo_script.md` makes some of these claims (SAM 3.1 segmentation in the
app, "99% accuracy"). Use this script, or fix those lines first.

## If the limit is 2 minutes

- Section 2: keep only "I wanted a teacher who listens. So I built one."
- Section 3: drop the computer keyboard cut and its sentence, but keep "our own code, not AI".
- Section 4: drop the drill and the "plan a session" paragraph.
- Section 5: drop the sentence about the benchmark numbers.
- Drop section 6.
