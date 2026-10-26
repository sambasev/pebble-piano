# TODO

## Coloured notes on book passages

Book pages are images of the printed page, so played notes can't be recoloured; today a
translucent green circle goes over each printed note played. Opened MIDI files already get real
green notes because PianoPad engraves them itself. Three ways to bring that to the book:

### 1. Score view for book passages, from the reference MIDI (next)

Add a third option to the passage view switch: **Passage | Page | Score**. Score draws the
passage from its reference MIDI with the same transcription and engraver as opened MIDI files,
so played notes turn green, waited-for notes are blue and held wrong keys show as red circles.

- `PlaySession.loadReference`: transcribe for book passages too (keep `score` set; `passage != nil`
  decides which view shows). Export MusicXML then also works for passages.
- Replace `showWholePage: Bool` with a `BookView` enum (`passage`, `page`, `score`);
  `ScoreView` takes `bookView == .page`.
- Grading tints: the score numbers measures in played order (repeats written out), so keep a
  separate `scoreMistakeMeasures = Set(report.flags.map(\.position.measure))` for `NotationView`;
  `mistakeMeasures` stays in printed numbers for the page view.
- Trade-off: only what's in the MIDI. No lyrics, dynamics, fingering or the book's layout, and
  repeats are written out in full.

### 2. Convert the book to MusicXML with optical music recognition (later milestone)

Run the PDF through OMR (e.g. Audiveris, open source) to get MusicXML that keeps lyrics, dynamics
and repeats, and draw the book from that instead of the PDF image.

- Needs a MusicXML reader (we only write it today).
- The engraver needs lyrics, dynamics, repeat barlines and other markings.
- OMR output needs checking page by page; clean engraving like this book recognises well, not perfectly.
- Fits the design doc's direction (MIDI for grading, MusicXML for notation) and gives stable note
  IDs for annotations.

### 3. Recolour the printed noteheads in the page image (alternative)

PianoPad already knows where each printed note is (the green circles line up with every note on
p. 29). Turn that notehead's dark pixels green in the page image, so the book looks as printed with
real green notes. Moderate work; the staff line through a notehead may pick up a little green.
