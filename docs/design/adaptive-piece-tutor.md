# Adaptive piece tutor

Open a MIDI file or annotated book passage in Practice and select **Teach me this piece**.
Start an assessment, hear the piece first, or choose note-by-note learning. Assessments use
a count-in and clicks; no backing track is needed. The deterministic grader supplies the
findings. A pure practice engine chooses note learning, slow practice, full speed and context
practice before another assessment. Passing a drill cannot complete the whole piece.

**AI settings** accepts a Meta Model API key stored in macOS Keychain and a model identifier
(default `muse-spark-1.3`). Test the connection there. Without a working key, all exercises
and deterministic feedback remain available. Only text score context and findings go to Meta;
piano audio detection remains local. Responses are explanations, never player commands.

Takes retain their normal MIDI and grading report. Tutor takes have an adjacent `.tutor.json`
sidecar containing exercise kind/range, actual speed, input mode and printed bar mapping.
Drills do not affect whole-piece aggregate scores. A fresh tutoring visit starts a new
assessment; previous recordings remain in learner history.

Manual verification: open Ode to Joy; start an assessment without backing audio; make a
mistake in a middle bar; inspect the grade and start the proposed drill; finish its note
learning and timed stages; reassess. Repeat with mic input and an annotated repeated book
passage. Check that switching learners or pieces ends tutoring and that offline feedback,
key removal, discarded attempts and silence leave the player usable.
