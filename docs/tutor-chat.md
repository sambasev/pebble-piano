# Chat with the piece tutor

The adult learner's Ask panel shares the open score with the tutor: pitches, rhythms,
suggested fingering, printed and played bar numbers, a rendered score excerpt, the current
guide/player state, the active lesson, saved lesson progress and recent grading evidence.
When the open piece came from a book, a chip above the question box ("Learning the Code Book 1 · page 47") shows that the page's picture and relevant page text are sent too; its ✕ leaves the page out and "Add page 47" puts it back.
Only the active learner's history is used. The tutor remembers a stated musical goal in
that learner's settings.

Examples:

- “Help me learn bar 4 slowly.”
- “Loop bars 3–4, right hand, at 60% speed.”
- “Play that passage for me first.”
- “My goal is to play this piece smoothly at 110 BPM.”
- “Start a lesson for this piece.”
- “Grade this take and tell me what to practise next.”
- “Open a beginner lesson on the notes I am missing.”
- “Stop coaching.”
- “Find me something easier by Bach.” / “Open Ode to Joy.” / “Let me hear the first one.”
- “Show me page 12 of the book.”

Each answer can offer up to three **follow-up chips** (“Slower, left hand only”, “Play it for
me”); tapping one asks it. A reply can also carry a short **plan** of up to three actions, run
in order: the next step starts only when the one before finishes (a demonstration ends or a
practice take is graded), without another model request. The chat shows what's queued
(“Then: Practise bars 3–4”). A failed step, a lesson or Stop ends the plan; a new question,
pausing coaching or changing piece cancels what's left.

**Honest about what ran.** The model writes its answer and its actions in one reply, before
the app runs anything, so it's told to say what it *will* do ("I'll play bar 3 slowly"),
never that it did. If the app then refuses an action (a take is recording, a demonstration is
playing, the bars don't exist), it asks the model once more with the reason
(`TutorChatInstructions.correction`) and replaces the bubble with that answer: what didn't
happen and what the learner can do. This extra call happens only on a refusal. A take with
fewer than two notes (a stray note the mic heard) isn't a performance: a tutor action discards
it instead of being refused; a take with real playing is never replaced.

The conversation is saved per learner in `Learners/<id>/tutor/chat.json` and reopens with the
same piece (even after relaunch, for up to a week). Switching learner keeps it for their
return. Opening another piece or **New chat** ends it: the tutor writes a few lines about it to
`notes.json` (the model's summary, or the questions asked when there's no key), and the latest
three notes go with every question as “Previous sessions”, so “what did we work on last
time?” has an answer.

**Progress and planning.** Every question carries this week's and last week's minutes and
days, pieces under way, the coach's next lesson, and the open piece's trend over its last 12
saved takes (`MistakeTrends`): first, latest and best note score, whether the last three takes
improved on the three before, full-speed in-time takes kept apart from slowed or note-by-note
ones, and the bars that went wrong in two or more takes with the usual slip ("bar 6, 4 of 7
takes, usually E4 played as D4"). Drill takes are mapped to printed bar numbers. `planSession`
saves today's plan (2–6 steps, 5–120 minutes) as a checklist card in the chat, kept in
`tutor/plan.json` for that day; the tutor sees which steps are ticked. `setGoal` can carry a
`goalDate`, shown to the tutor with the days left; a new goal without a date drops the old date.

**App help.** Questions that look like app help (a keyword check in `TutorAppGuide`), or any
question after a take where under half the expected notes were heard, carry the app guide
and input diagnostics: chosen input, mic on and level, calibration age, connected Bluetooth
MIDI and notes heard in the latest take. `openCalibration`, `switchInput` and `openSettings`
(input, practice or AI settings) only offer a button in the chat; nothing changes until the
learner presses it, and “Not now” drops it. `markPlayedRight` copies the latest graded take of
the open piece, its report and a label to `PlayedRight/` in Application Support for checking
the grader; the grade is unchanged. Each of these ends a plan.

**Children.** A child learner never types. The chat shows big buttons instead of a text box:
“What's this note?”, “Play it for me”, “Make it slower”, “I'm stuck”, and a smaller “For
grown-ups: how is it going?”. Each sends a fixed question with the child prompt
(`TutorChatInstructions.child`: three short sentences at most, no percentages or grading
words). Only `playNotes`, `highlight`, `setTempo` and `stop` can run for a child, at most two
per answer; anything else the model asks for is dropped. The grown-ups' button is answered in
adult language from progress and trends, with no actions. Follow-up chips, the coaching
toggle, the book toggle and AI settings are hidden for children.

**Streaming.** Answers stream in: `ModelClient.chatStreaming` reads the server-sent events
as they arrive, and `TutorChatStreaming.partialReply` pulls the reply text out of the
unfinished JSON. Text shows only once `"on_topic": true` has arrived, so an off-topic answer
never flashes before the refusal. Actions still run only on the finished, checked reply.

Practice requests prepare one repetition at a time. Timed exercises wait for **Start practice**
before their count-in; note-by-note exercises wait for the learner's first note. Empty timed
runs return to ready without a grade or saved take. Tempo requests use `setTempo`, keeping
the current passage and hand instead of grading the take to change settings. A model's
`gradeTake` request offers **Grade take**; only pressing that button ends the take early.
With coaching enabled, each
completed take sends fresh grader evidence to the tutor, which can repeat a passage,
adjust speed or hand, continue a lesson step, or stop. Silent takes do not generate
automatic model requests. The pause button beside Send disables these follow-ups without
discarding the current recording. A requested Stop keeps a played take ungraded for the learner
to finish with **Grade take**.
The Tutor button in the header keeps chat accessible while a stock Learn lesson is open.

### Demonstrations and generated exercises

- “Teach me the G major scale, two octaves, hands together” → `practiceExercise`. The
  exercise comes from `ExerciseGenerator` (`Sources/PianoLessons/ExerciseGenerator.swift`), not
  the model: major, natural minor and harmonic minor scales, arpeggios, broken chords and
  five-finger patterns, in any key, 1–2 octaves, right, left or both hands, with standard
  fingering tables (C major RH 1-2-3-1-2-3-4-5, F major RH 4 on B♭). It opens as the practice
  piece (saved under `TutorExercises/` in app support, its fingering shown as printed), stays
  within C2–C6, and is graded by the normal grader. Hands together puts the left hand an octave
  lower on its own track. Only two-octave broken chords with both hands in A, B♭ and B don't
  fit the keyboard; the tutor says so.
- “Play a C minor chord” → `playNotes`: up to 32 named notes (C2–C6, “C4+E4+G4” for a chord),
  one beat each at `tempoBPM` (30–200, default 80), through the audition path so the keys
  light up. The open piece is left as it was. Like `listenPassage` it waits for the player,
  so “play it, then let me try” runs `playNotes` then `practiceExercise`.
- “Show me where” → `highlight`: up to 16 printed bars of the open piece and/or 16 keys, for
  four seconds, on the score and the Practice keyboard.
- “Quiz me on intervals” / “Help me read faster” → `startEarTraining {level?}` /
  `startSightReading`: the learner's next unlocked page of that course (in that level when
  given). Like lessons, they end a plan.

Player actions are checked locally: bars must exist, an excerpt is at most 16 bars,
speed must be 25–100%, hand separation requires separate MIDI tracks, and stock lessons
must be unlocked. An active take must be graded before another exercise replaces it.
Cancelled or stale replies cannot act after a piece or learner changes. Model output
never determines a pass or awards mastery; grading remains deterministic.

**Library and navigation.** `searchLibrary {query, composer?, difficulty?}` searches, on the
device and without another model request, the Music Library catalog, the goal songs, the open
book's passages, pieces read from books and the learner's recent pieces. The top five go into
the chat as an app observation, each as `#n [id] title — composer · level · where`, with a
stable ID (`catalog:mutopia-61`, `goal:odeToJoy`, `passage:<id>`, `book:<folder>`,
`recent:<piece id>`). A search doesn't wait for the player, so a plan can go on to
`openPiece {pieceRef}`, whose `pieceRef` must be an ID a search returned in this conversation
or `#1`–`#5` for the latest search's results; titles and other free text are refused, and the
ID is checked again against what exists now. Opening goes through the usual paths
(`openCatalogPiece` after the validated download, `selectPassage`, the saved piece, or the recent
file's bookmark), switches to Practice and keeps the conversation. `previewPiece` plays a
Music Library piece in that tab (other music has no preview); `openBookPage {page}` shows a page
of the open piece's book (or the one open in Books) there. Opening, previewing or showing a
page ends the plan. A new chat forgets what was found. The context's **Library** section lists
the catalog's counts by level, a suggested level from `LearnerSkills` (Intermediate only after
three passed pieces, hands together and 96 BPM), the open piece's level, recent pieces, the
goal song and, on the Music Library tab, its filters and selected piece, so “something easier”
has something to compare against.

Context is bounded: score excerpts prioritize requested/current/error bars; recent saved
takes, lesson history and model conversation are capped. An excerpt image is rendered
from music data; it does not capture other apps or the desktop.

Notes off the keyboard, unknown exercises or keys, more than two octaves and bars outside the
piece are refused without changing the player.

Validation: `swift test --filter 'TutorChat|PiecePractice|LearnerStoreTests|LessonProgress|ExerciseGenerator'`
(includes `TutorChatMemoryTests`, `TutorChatLibraryTests`, `TutorChatDemoTests`,
`TutorChatProgressTests`, `MistakeTrendsTests`, `TutorChatHelpTests`, `TutorAppGuideTests` and `TutorChatChildTests`).
The opt-in live tutor test requires `PIANOAI_LIVE=1` and `MODEL_API_KEY`; it sends a synthetic
eight-bar score and checks score reading and the requested passage action against Meta.

## Evals

- **The app end to end:** `PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter TutorLiveEvalTests`
  runs 20 scenarios (sections A–G of the plan) through the real app against the live model:
  real pieces, takes played on the on-screen keyboard and graded, the real library (opening
  downloads the piece), lessons, memory and action checks. Each case passes on what the app
  did. Results: `docs/tutor_live_evaluation.md`.
- **The model alone:** `python3 scripts/evaluate_tutor.py` runs 31 short-context checks
  (guardrails, jailbreaks, pedagogy, a scanned Beyer page, single actions). It reads the
  instructions and schema from `docs/tutor_contract.json`, which the app's code writes;
  `TutorContractTests` fails when the file is stale (`UPDATE_TUTOR_CONTRACT=1 swift test
  --filter TutorContractTests`). Results: `docs/tutor_evaluation.md`.
