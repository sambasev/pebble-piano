# Pebble Piano: 3-minute demo video script

Meta Hackathon, Multimodal AI and Meta Model API track. Screen recording with voiceover, plus a
camera on the hands and piano where marked. About 400 words of voiceover, which is roughly 2:50
at a relaxed pace and leaves room for the app to make sound.

Everything claimed here matches the README and the evaluation docs. Tutor replies change from
run to run, so record real ones and keep the voiceover general where it describes them.

## At a glance

| Time | Scene | What the viewer should take away |
| --- | --- | --- |
| 0:00–0:20 | Hook | It hears a wrong note on a real piano and says which one |
| 0:20–0:40 | The problem | Practising alone, nobody tells you what went wrong |
| 0:40–1:15 | Listens and grades | Our own on-device detection and grading, MIDI or mic |
| 1:15–1:55 | The tutor (Muse Spark) | Coaching from measurements: names the bar, plays it, sets the drill |
| 1:55–2:30 | Your own book (Muse Wonder) | A printed page becomes a piece you can play and be graded on |
| 2:30–2:45 | Everything else | Lessons, ear training, sight reading, child mode, library |
| 2:45–3:00 | Close | Measurements, not guesses; audio stays on the Mac |

---

## Scene 1: Hook (0:00–0:20)

**On screen:** Camera over the shoulder at an acoustic piano, Mac beside it, Pebble Piano on
Practice with **Mic** on and **Guide** on. Play the passage and hit one wrong note on purpose.
Cut to the screen: the red circle on the staff and the status line *"You played E4 · play D4"*.

**Voiceover:**
> That was a wrong note. Pebble Piano heard it through the microphone, on a real piano, and it
> knows exactly which one: an E where the book says D.

---

## Scene 2: The problem (0:20–0:40)

**On screen:** Slow push in on the printed book on the music stand. Maybe a sticky note that
says "practise bar 6".

**Voiceover:**
> Most piano learning happens alone, between lessons, from a book. Nobody is there to say which
> bar went wrong, or why, or what to practise next. So mistakes get practised in.
> We built a tutor that listens.

---

## Scene 3: It listens and grades (0:40–1:15)

**On screen:**
1. Press **Space**: the passage plays and the keys light purple.
2. Play it: played notes get green circles on the page, the playhead waits on each chord.
3. Finish. Auto-grade fires and the report appears: pass or fail, notes, rhythm, flagged
   mistakes with bar and beat.
4. Quick cut: the same with a MIDI keyboard, or the computer keyboard (A S D F).

**Voiceover:**
> Play on a MIDI keyboard, an acoustic piano through the Mac's microphone, or even the computer
> keyboard. The note detection and the grading are our own code, not AI: signal processing and
> score alignment, running on the Mac. Every note is marked right, wrong, missed or extra, with
> its bar and beat, plus rhythm and tempo. Your piano audio never leaves the computer.

---

## Scene 4: The tutor, on Muse Spark (1:15–1:55)

**On screen:** Open the chat panel right after the graded take.
1. Type or tap: *"What went wrong?"* The answer streams in and names the bar and the slip.
2. Tap a follow-up chip such as *"Play it for me"*: the app plays the bar, keys light.
3. Ask *"Loop bars 3–4, right hand, at 60% speed"*: the drill starts.
4. Optional: *"How did I do this week?"* or *"Plan a 15-minute session"*, showing the checklist card.

**Voiceover:**
> Then you can just ask. The tutor runs on Meta's Muse Spark, and it doesn't guess from audio. It
> reasons from the grader's measurements: this take, your last dozen takes on this piece, and the
> bars you keep missing. It can play a passage for you, loop the hard bars slowly, plan a session
> and remember your goals. And it's honest: if it can't do something right now, it says so,
> instead of pretending.

**Tip:** The live evaluation (`docs/tutor_live_evaluation.md`) has 22 real conversations that
passed. Use one of those questions so the answer is likely to be good on camera.

---

## Scene 5: Your own book, read by Muse Wonder (1:55–2:30)

**On screen:**
1. **Books** → import a PDF page (Beyer Op. 101 works well, it's from 1895).
2. Select the lines and read them. Show the result appearing.
3. Optional: flash `docs/charts/hybrid_ablation_breakthrough.png`.
4. Play the newly read piece: green circles land on the printed notes.

**Voiceover:**
> And it works with the book you already own. Muse Wonder reads the printed page line by line:
> the metre, the barlines, the rhythms, both hands. Vision models sometimes put a note one line
> off, so we check each pitch against the notehead's position on the staff. On our benchmark that
> takes a book from 1895 to about 95% of notes right, and modern engravings to 100%. A photo of a
> page becomes a piece you can play and be graded on.

---

## Scene 6: Everything else (2:30–2:45)

**On screen:** A fast montage, one to two seconds each: the **Learn** lesson map, an ear
training question, a sight reading question answered by playing the key, child mode, the
**Music Library** with 30 pieces.

**Voiceover:**
> There's a full beginner path too: lessons, ear training, sight reading, a child mode, and a
> library of 30 free classical pieces.

---

## Scene 7: Close (2:45–3:00)

**On screen:** Back to the hands at the piano, playing the passage cleanly. The report says pass.
End card: **Pebble Piano**, "A piano tutor that listens", the GitHub URL, "Built with Muse Spark
and Muse Wonder".

**Voiceover:**
> Our own code measures how you played. Meta's models turn those measurements into teaching.
> Pebble Piano: a piano tutor that listens.

---

## Before recording

- [ ] Meta key saved in **⋯ → AI settings…**, connection check green.
- [ ] Quiet room. Turn on **Mic** and stay silent for the first second while it measures the room.
- [ ] Optional: run **Calibrate piano (mic)…** on the piano you'll film.
- [ ] Do the whole Scene 3–4 run once off camera: the tutor takes several seconds to reply, and
      it can answer differently each time. Speed up the wait in the edit if needed.
- [ ] Import the Scene 5 book page beforehand too, so you know which lines read well. Reading
      takes about a minute per line; record it once and cut the wait.
- [ ] Hide the Dock and notifications; use a large window so the staff reads on a phone screen.
- [ ] Record the app's sound directly as well as through the room mic.

## Things not to say

These would be wrong about the app today:

- That SAM 3.1 or voice transcription is part of the app. The client supports them, but the app
  only uses them in the AI settings connection check.
- That Bluetooth MIDI has been tested. It hasn't (see *Known issues* in the README).
- That the mic works in a noisy room. It misses many soft notes there; film somewhere quiet.
- That there's an iPad or iPhone app. It's Mac only.

The older `docs/video_demo_script.md` is mostly about the reading benchmark and says some of
these things (SAM 3.1 segmentation in the app, "99% accuracy"). Use this script, or fix those
lines first if you use that one.

## If the limit is 2 minutes

Cut Scene 2 down to its last two lines, drop step 4 of Scene 4 and Scene 6 entirely, and
shorten Scene 5 to the import, the read and the play-through.
