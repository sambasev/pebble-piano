# Chat with the piece tutor

The adult learner's Ask panel shares the open score with the tutor: pitches, rhythms,
suggested fingering, printed and played bar numbers, a rendered score excerpt, the current
guide/player state, the active lesson, saved lesson progress and recent grading evidence.
When **Use [book]** is on, the book page and relevant page text are included as well.
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

Each answer can offer up to three **follow-up chips** (“Slower, left hand only”, “Play it for
me”); tapping one asks it. A reply can also carry a short **plan** of up to three actions, run
in order: the next step starts only when the one before finishes (a demonstration ends or a
practice take is graded), without another model request. The chat shows what's queued
(“Then: Practise bars 3–4”). A failed step, a lesson or Stop ends the plan; a new question,
pausing coaching or changing piece cancels what's left.

The conversation is saved per learner in `Learners/<id>/tutor/chat.json` and reopens with the
same piece (even after relaunch, for up to a week). Switching learner keeps it for their
return. Opening another piece or **New chat** ends it: the tutor writes a few lines about it to
`notes.json` (the model's summary, or the questions asked when there's no key), and the latest
three notes go with every question as “Previous sessions”, so “what did we work on last
time?” has an answer.

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

Player actions are checked locally: bars must exist, an excerpt is at most 16 bars,
speed must be 25–100%, hand separation requires separate MIDI tracks, and stock lessons
must be unlocked. An active take must be graded before another exercise replaces it.
Cancelled or stale replies cannot act after a piece or learner changes. Model output
never determines a pass or awards mastery; grading remains deterministic.

Context is bounded: score excerpts prioritize requested/current/error bars; recent saved
takes, lesson history and model conversation are capped. An excerpt image is rendered
from music data; it does not capture other apps or the desktop.

Validation: `swift test --filter 'TutorChat|PiecePractice|LearnerStoreTests|LessonProgress'`
(includes `TutorChatMemoryTests`).
The opt-in live tutor test requires `PIANOAI_LIVE=1` and `MODEL_API_KEY`; it sends a synthetic
eight-bar score and checks score reading and the requested passage action against Meta.
