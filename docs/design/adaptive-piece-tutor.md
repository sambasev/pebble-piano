# Adaptive piece tutor

Open a MIDI file or annotated book passage in Practice and select **Teach me this piece**.
Start an assessment, hear the piece first, or choose note-by-note learning. Assessments use
a count-in and clicks; no backing track is needed. The deterministic grader supplies the
findings. A pure practice engine chooses note learning, slow practice, full speed and context
practice before another assessment. Passing a drill cannot complete the whole piece.

**AI settings** opens the shared hackathon settings screen. Save a Meta Model API key
there and choose the Practice tutor model (default `MetaModels.spark`). The Practice tutor
uses Meta; Fireworks and Modal settings remain available for other hackathon features. Without a working key, all exercises
and deterministic feedback remain available. Only text score context and findings go to Meta;
piano audio detection remains local. Responses are explanations, never player commands. Tutor requests use `PianoAI.ModelClient`
and are included in the shared usage totals. Both the Practice toolbar and tutor panel open
the same settings screen.

Takes retain their normal MIDI and grading report. Tutor takes have an adjacent `.tutor.json`
sidecar containing exercise kind/range, actual speed, input mode and printed bar mapping.
Drills do not affect whole-piece aggregate scores. A fresh tutoring visit starts a new
assessment; previous recordings remain in learner history.

Manual verification: open Ode to Joy; start an assessment without backing audio; make a
mistake in a middle bar; inspect the grade and start the proposed drill; finish its note
learning and timed stages; reassess. Repeat with mic input and an annotated repeated book
passage. Check that switching learners or pieces ends tutoring and that offline feedback,
key removal, discarded attempts and silence leave the player usable.


## Hackathon integration

`codex/hackathon-piece-tutor` starts at hackathon `6a97153`, with only the focused tutor
commit ported from the TestFlight-based worktree. Learn navigation, timed Continue,
the tempo strip, app version and shipping configuration remain from hackathon.

The shared `APIKeyStore` owns the credential. On normal app startup, a one-time migration
copies the legacy tutor key only if no shared Meta key is configured. Existing shared keys
win. Failed copies retain the old key and retry on a later launch. Successful copies remove
the old entry. The legacy `TutorModel` preference remains a fallback for the new shared
`AISettings.tutorModel` preference. Removing a shared key after migration does not restore
an old key automatically.

Tests use a fake shared transport and injected feedback clients; they make no network
requests by default. To make exactly one live text tutor request with your configured key:

```sh
PIANOAI_TUTOR_LIVE=1 swift test --filter ModelTutorFeedbackTests/testOneLiveTutorCallWhenEnabled
```

The live check skips when no Meta key is available and prints the tutor reply plus shared
usage output. It does not run the broader SAM or transcription checks.
