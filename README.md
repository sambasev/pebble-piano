# PianoGrader

Milestone 0 of the piano eBook tutor: a MIDI rater. It grades a played take against
a reference MIDI passage, using a rubric file, and reports which notes were right,
wrong, missed or extra, plus rhythm and tempo.

- `PianoGraderCore`: the grading library. Pure Swift, no UI and no CoreMIDI, so the
  macOS/iOS app can use it unchanged later.
- `grade`: a command-line tool that grades a recorded take, records one live from a
  MIDI keyboard, or re-grades your labelled fixtures.

## Build and test

Requires Xcode 15+ (Swift 5.9) on macOS 13 or later.

```sh
swift build
swift test
```

Live capture uses CoreMIDI, so it only works on macOS. The library and tests build anywhere Swift runs.

## Try it on the examples

```sh
swift run grade --ref Examples/five-finger.mid --take Examples/take-clean.mid
swift run grade --ref Examples/five-finger.mid --take Examples/take-wrong-note.mid
swift run grade --ref Examples/five-finger.mid --take Examples/take-rushed.mid
swift run grade --ref Examples/five-finger.mid --take Examples/take-skipped-with-warmup.mid --json -
```

Expected results:

| Take | Verdict | Why |
| --- | --- | --- |
| `take-clean.mid` | pass | Small timing jitter only |
| `take-wrong-note.mid` | fail | m1 b2: played E4, expected D4 |
| `take-rushed.mid` | pass, with a flag | m2 b1: came in 60% early (rhythm is fine on average) |
| `take-skipped-with-warmup.mid` | fail | m2 b1: missed G4; the two warm-up notes are ignored |

## Play live

Connect your keyboard over USB (or pair it in Audio MIDI Setup → Bluetooth), then:

```sh
swift run grade --ref Examples/five-finger.mid --live
```

Recording stops 2 seconds after your last note (`--silence` changes this). The take is
saved under `takes/` and then graded.

## PianoPad: the Mac app

The quickest way to test. In Xcode choose the **PianoPad** scheme (Product → Scheme → PianoPad)
and press ⌘R. A window opens with an on-screen keyboard:

- Press **Space** (or **Listen**) to hear the reference through the built-in piano, with its keys
  lit purple as they play. The speed menu plays it at 50%, 75% or 100%.
- Play on a MIDI keyboard, or on the computer keyboard in the musical-typing layout below. The app
  sees real key presses and releases, so note lengths are real too.
- Keys turn blue while held. With **Guide** on, the next expected note is green and a wrong note
  turns red while you hold it. The playhead waits on each chord until it is played cleanly: all its
  notes, and no other key struck with them. Notes you've played correctly turn green, and the notes
  the playhead is waiting for are blue (on book pages, a green circle goes over each printed note you
  played; after a repeat sign they start again). D+E doesn't pass for D; a wrong key means playing the
  chord again (keys still held from the previous chord don't count against you).
- Recording starts on your first note. Press **Return** or click **Grade** to finish the take, or
  **Esc** to discard it. With **Auto-grade** on (the default), the take is graded by itself 1.5 s
  after you finish the passage: once the guide reaches the last note and you let go of the keys.
  Playing again after a grade starts a new take.
- The report shows pass or fail, each level, and the flagged mistakes. **Save take…** writes the
  take as a `.mid` you can grade with the CLI or keep as a fixture.
- **See where you are on the staff.** With **Guide** on, while you hold a key the guide didn't expect,
  a see-through red circle sits on its line or space in the playhead's column, next to the green note
  you should play, and the status line says "You played E♭4 · play D4". It disappears as soon as you
  let go. On book pages it lands on the printed staff: PianoPad finds the staff lines in the page
  image, or uses `staff` from the annotations when a measure gives one.
- **Open any MIDI file** (⋯ menu → Open MIDI file…). It is transcribed into a score and engraved in
  the window, and the playhead waits on each chord until you play it (wait mode), with green notes for
  what to play next. **Export MusicXML…** saves the transcription for MuseScore, Dorico or Finale.
- It opens the bundled book page by default. Use the passage picker for another passage, the ⋯ menu
  for a MIDI file, and the rubric picker for Beginner, Intermediate or your own rubric file.
- Computer-keyboard notes play through macOS's piano sound (**Sound** toggle). MIDI notes don't,
  since your piano makes its own. **Rescan MIDI** picks up a keyboard connected after launch.

## Microphone input (acoustic pianos)

Turn on **Mic** in PianoPad to play an acoustic piano without MIDI. The detector
(`PianoNoteDetector`, our own code with no third-party models) is score-informed DSP:

1. A constant-Q filter bank (a third of a semitone per bin, A0 to 7 kHz) analyses the mic every 8 ms.
2. A dictionary holds a harmonic template for each of the 88 keys, with inharmonicity and a
   small mic's weak bass.
3. Non-negative matrix factorisation explains each spectrum as a mix of those templates plus
   noise. Keys the score expects are cheap to use; neighbours, octaves and other keys cost more.
4. Notes are only reported at a hammer strike, which is confirmed by high-frequency spectral
   flux and a jump in loudness. Strings ringing on, or resonating in sympathy, can't trigger notes.

- **Latency:** the detector decides about 70 ms after a key is struck. Audio buffering adds
  roughly 5–10 ms on top of that.
- **Room check:** for the first ¾ second after Mic turns on, the detector measures the room's
  background noise, so stay quiet. It then ignores anything not clearly louder than that noise
  (this removes the phantom notes that hiss, phone gain and clicks used to cause).
- **Lenient extra keys:** a microphone can hear keys that weren't played. Extras it hears still
  show red, but they don't hold up wait mode the way they do with MIDI. A wrong key played
  *instead* of the right one is still caught.
- **Muted during playback:** the mic ignores sound while PianoPad plays the passage itself.
- **Recordings:** while Mic is on, what it hears is saved to `~/Music/PianoPad Mic/` (a WAV plus
  a log of expected and detected notes), for tuning. Turn Mic off to finish the file.
- **Accuracy:** measured on a synthetic benchmark (sampled piano, simulated room, beginner
  pieces):

  | Condition | Clean chords accepted | Falsely flagged wrong | Mistakes caught |
  |---|---|---|---|
  | Dry | ~84% | ~2% | ~94% |
  | Room | ~83% | ~1% | ~91% |
  | Noisy room | ~24% | ~0% | ~89% |

  Noisy rooms mostly miss soft notes. On a real piano recorded with a phone, a C3–C4–C5
  calibration was detected exactly, with no extra notes.

**Calibration (optional).** In the ⋯ menu, **Calibrate piano (mic)…** takes about 10 seconds:
stay quiet, then play middle C, D and E (C4, D4, E4), letting each ring. The app measures
your piano through your mic: tuning, string inharmonicity and how loud each overtone is. All 88
key templates are then built from those measurements; keys outside C4–E4 use the nearest one's.
Wrong keys, too-quiet notes and sounds that don't decay like a string (humming) are rejected with
a message. The profile is saved in Application Support and used whenever Mic is on; **Clear
piano calibration** goes back to the generic model. On our test recordings calibration catches
more real notes but also adds some false ones, so it's off until you run it.

To try the detector on a recording:

```sh
swift run grade listen take.wav                                     # print the notes it hears
swift run grade listen take.wav --truth played.mid --guide score.mid  # score it against MIDI
swift run grade calibrate cal.wav                                   # measure a piano (quiet, C4, D4, E4)
swift run grade listen take.wav --calibration cal.wav               # listen with that calibration
python3 scripts/make_detector_bench.py /tmp/bench                     # build the synthetic benchmark
```

## Play on the computer keyboard (musical typing)

For quick testing without a piano, use the Logic/Ableton musical-typing layout:

```sh
swift run grade --ref Examples/five-finger.mid --keys
```

```
    [W]   [E]         [T]   [Y]   [U]         [O]   [P]
    C#4   D#4         F#4   G#4   A#4         C#5   D#5
 [A]   [S]   [D]   [F]   [G]   [H]   [J]   [K]   [L]   [;]   [']
 C4    D4    E4    F4    G4    A4    B4    C5    D5    E5    F5

[Z]/[X] octave down/up   [C]/[V] velocity down/up   [Return] finish   [Esc] cancel
```

The map is printed when recording starts, with labels for the current octave. Notes play
through macOS's built-in piano (`--no-sound` turns this off), and `--octave 3` starts an
octave lower. Press Return to finish; the take is saved under `takes/` and graded like any
other. `--label` works here too.

Terminals report key presses but not releases, so every typed note is 0.4 s long.
That doesn't matter yet because grading uses note onsets only. Tap keys rather than
holding them, since a held key auto-repeats. For chords, press the keys together: a few
tens of milliseconds apart still counts as one chord (`chord_window_ms`, 50 by default).

## The exit gate: fixtures

Label each take with your own verdict. It is saved as a fixture together with its
reference and rubric:

```sh
swift run grade --ref lesson12a.mid --live --rubric Rubrics/beginner.md --label pass
swift run grade --ref lesson12a.mid --live --rubric Rubrics/beginner.md --label fail
```

Then re-grade them all:

```sh
swift run grade check --fixtures fixtures
```

This prints each fixture with your label and the grader's verdict, overall agreement,
and how many of each mistake type were flagged. It exits non-zero below the gate
(90% by default). The milestone is done when you have 20 takes across 5 passages,
agreement is at least 18/20, and every mistake type has been caught at least once.
Run `check` again after any threshold change.

## Rubrics

A rubric is Markdown with YAML front matter (or plain YAML). The front matter holds
the thresholds. The body is guidance for the future tutor, exposed as `Rubric.guidance`.
Missing keys fall back to the beginner defaults. See `Rubrics/beginner.md` and
`Rubrics/intermediate.md`.

| Key | Meaning | Beginner default |
| --- | --- | --- |
| `checks` | Levels that decide pass/fail: `notes`, `rhythm`, `tempo` | `[notes, rhythm]` |
| `chord_window_ms` | Notes starting this close together count as one chord | 50 |
| `target_bpm` | Target tempo; otherwise the reference file's tempo | from file |
| `notes.min_accuracy` | Minimum score: (correct − penalty × extras) ÷ expected | 0.95 |
| `notes.extra_note_penalty` | Notes deducted per extra note | 0.5 |
| `rhythm.max_mean_ioi_error` | Mean interval error, as a share of the notated duration | 0.25 |
| `rhythm.flag_ioi_error` | Flag single intervals worse than this | 0.40 |
| `tempo.tolerance` | Allowed tempo deviation from the target | 0.15 |
| `tempo.max_steadiness_cv` | Allowed variation in local tempo | 0.20 |

## How grading works

1. **Parse.** Both files become note events (pitch, onset, offset, velocity). The sustain pedal and velocity are recorded but not graded yet.
2. **Group chords.** Notes starting within `chord_window_ms` of each other become one event.
3. **Align.** Needleman–Wunsch over chord events. Pairing two events costs 1 − (shared pitches ÷ all pitches), and skipping one costs 1. So a wrong note is reported as a wrong pitch, not as a miss plus an extra. Unmatched notes before the first match and after the last are warm-up noodling and are ignored.
4. **Classify notes.** Each note is correct, wrong pitch, missed or extra, and gets a position (measure and beat) from the reference's ticks and time signature.
5. **Timing.** Fit performed onset seconds against reference beats with least squares. The slope gives the played tempo. Each interval between consecutive matched events is compared with slope × notated interval, which gives the rhythm error. A single rushed note produces one short and one long interval; only the first is flagged.
6. **Rubric.** Thresholds turn the metrics into pass or fail for each graded level.

The JSON report (`--json`) contains the verdict, level results, note counts, timing,
flags in score order, and one entry per note for colouring the keyboard later.

## From MIDI to a score (and MusicXML)

PianoPad and the `transcribe` command share one transcription:

```sh
swift run grade transcribe song.mid -o song.musicxml
swift run grade transcribe song.mid -o song.musicxml --svg song.svg   # also draw it as PianoPad does
```

- **Grid.** Note starts and ends snap to sixteenth notes, using the file's ticks (so tempo changes
  don't matter). There are no triplets yet.
- **Hands.** Two tracks (or one track with two channels) become the treble and bass staves, the higher
  one on top. Otherwise notes from middle C up go to the treble staff (`--split` changes the pitch);
  music that fits one clef gets one staff. Drums (channel 10) are left out.
- **Key.** From the file's key signature, else guessed from the notes (`--fifths` overrides). Notes are
  spelled for the key, with accidentals reset at each barline.
- **Rhythm.** Notes crossing a barline, or lengths no single note value shows, are tied. Eighths and
  sixteenths inside a beat are beamed.
- **One voice per hand.** Within a staff, a note held past the next note's start is cut there, and
  chord notes share one length. Pickup bars aren't detected, so a piece starting on an upbeat has its
  barlines a beat early.

The MusicXML is version 4.0 and validates against the official schema. On screen, scores are engraved
with outlines from the [Bravura](https://github.com/steinbergmedia/bravura) music font (SIL Open Font
License, see `LICENSES/Bravura-OFL.txt`); `scripts/make_glyphs.py` regenerates them.

## Making reference MIDI for a passage

- Enter the passage in MuseScore, set the tempo and time signature, and export as MIDI. This is the most accurate option.
- Or play it carefully on the digital piano with `--live --out ref.mid`, then fix any timing in a MIDI editor.
- Keep one passage per file. Measure numbers in flags count from the start of the file, so start each file at the passage's first measure.

## Known limits (milestone 0)

- Tempo is fitted globally, so a take that slows down steadily shows up as rhythm error. A sliding-window fit can come later.
- Measure numbers assume the first time signature holds throughout, and that there is no pickup bar.
- Repeated identical pitches inside one chord are counted once.
- There is no count-in or metronome during live capture.

## Ship PianoPad to TestFlight (Mac)

`App/project.yml` wraps PianoPad as a sandboxed Mac app (bundle, icon, microphone permission),
because App Store Connect only accepts archived app bundles, not Swift package executables.

The quick way: `App/ship.sh` does steps 1 and 4 (merge, backing tracks, project, archive), and
`App/ship.sh --upload` uploads once the app record exists.

1. **Generate the project:** `brew install xcodegen`, then
   `cd App && PIANOPAD_TEAM=<team ID> xcodegen && open PerfectPiano.xcodeproj`
   (team ID: developer.apple.com → Account → Membership details).
2. **Smoke-test the sandbox:** run the **PianoPadApp** scheme (⌘R). Check the book and examples
   load, MIDI input works, the microphone prompt appears and the mic grades notes, and importing a
   backing track still plays after quitting and relaunching.
3. **Create the app record:** App Store Connect → Apps → + → New App → macOS, bundle ID
   `com.sambasev.perfectpiano`. The name must be unique on the store; if "PianoPad" is taken, any
   name works here, it doesn't change the app.
4. **Archive and upload:** in Xcode choose *Any Mac* as destination, Product → Archive, then
   Distribute App → TestFlight & App Store. Processing takes 15–60 minutes.
5. **Invite testers:** for same-day access, add friends as App Store Connect users (Users and
   Access, any role) and put them in an internal TestFlight group; internal builds skip Beta App
   Review. External groups and public links need the first build reviewed (usually about a day).
   Testers install TestFlight from the Mac App Store and accept the invite.

`ship.sh` gives every archive a new build number (date and time), so uploads never clash.

To ship backing tracks with the app, put them in `BackingTracks/` (see its README).

Differences in the packaged app:
- Imported backing tracks are copied into the app's library, since the sandbox can't reopen the
  original file on a later launch.
- Mic recordings for detector tuning are off. Turn them on with
  `defaults write com.sambasev.perfectpiano RecordMicDebug -bool YES`; they land in
  `~/Library/Containers/com.sambasev.perfectpiano/Data/Music/PianoPad Mic`.
- **Choose Book…** can open only the annotations file the user picks, not the PDF beside it, so
  only the bundled book works.
