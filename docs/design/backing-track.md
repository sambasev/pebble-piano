# Play-along with a backing track

Branch: `feature/backing-track`.

The student plays along with a recorded backing track. While they keep up, the track plays on as
normal. If they fall behind or miss too much, playback stops, rewinds to the start of the current
bar, counts in, and starts again from there. A tempo control slows the track and the expected notes
together without changing the backing's pitch.

This is a new **Play-along** mode next to the existing **Wait** mode (`WaitGuide`, which holds on
each chord until it's played).

## Decisions

- **Backing is an audio file** (m4a, mp3 or wav) played through Apple's built-in time stretching
  (`AVAudioUnitTimePitch`). We don't use MIDI backing for now.
- **The backing is annotated by hand.** You set where beat 1 of bar 1 falls in the file, plus its
  tempo, time signature and key, so bar positions can be computed for seeking.
- **Mistakes are lenient.** Wrong notes alone never stop playback. A bar fails only when enough of
  its expected chords are missed or played too late, and the beginner threshold forgives a slip.
- **Rewind goes to the start of the current bar**, followed by a one-bar count-in.

## Annotation

Each passage in the book's annotations JSON gets an optional `backing` entry:

```json
"backing": {
  "file": "../Backing/ltc-p29-rh-seconds.m4a",
  "startSeconds": 1.84,
  "bpm": 92,
  "timeSignature": "4/4",
  "key": "C",
  "countInBars": 1
}
```

- `startSeconds` is the time of beat 1 of bar 1 in the audio. Any pickup or intro before it plays
  only when starting from bar 1.
- The backing is assumed to keep a steady tempo. A track that drifts would need a list of beat
  times instead of one `bpm`; that's left for later.
- `key` is informational for now. It can later be used for transposition through the same
  time-pitch unit's pitch setting.
- Bars are numbered in **played order**, so repeats in `playOrder` map to their own stretch of
  audio.

Bar `n` starts at `startSeconds + (n - 1) * beatsPerBar * 60 / bpm` seconds of audio.

## Tempo

- A tempo factor (for example 50%–110%, default 100%) sets the time-pitch unit's `rate`. Pitch is
  unchanged.
- Expected note times are worked out in beats from the reference MIDI. The beat clock turns beats
  into seconds using `bpm × factor`, so the judge, playhead and audio always agree.
- The reference MIDI's tempo should match `bpm`. Loading warns if the two differ by more than a few
  percent.
- The metronome click and count-in follow the same clock.

## Components

**Core (`PianoGraderCore`, pure and unit-tested)**

- `BackingAnnotation`: Codable, and added to `PassageAnnotation` as `backing`.
- `BeatClock`: converts between beats and audio seconds given `startSeconds`, `bpm`, the time
  signature and the tempo factor. It also gives `barStart(containingBeat:)`.
- `PlayAlongJudge`: works like `WaitGuide`. It is fed the reference chords (with their beat
  positions), note-ons and the clock's current beat, and it returns `.onTrack` or
  `.rewind(toBar:)`.
  - A chord is **hit** if all its notes are struck within `[beat − early, beat + late]`. Extra keys
    don't cancel it.
  - A chord is **missed** once the clock passes `beat + late` without it being hit.
  - A bar **fails** when its misses exceed the rubric threshold (beginner: more than 1 miss, or
    more than 30% of the bar's chords). Otherwise misses are recorded but play continues.
  - Windows and thresholds come from the rubric (new `play_along` section). Mic input gets wider
    windows because detection lags.

**IO (`PianoGraderIO`)**

- `BackingPlayer`: an `AVAudioEngine` with an `AVAudioPlayerNode`, followed by
  `AVAudioUnitTimePitch`, followed by the mixer. It supports `play(fromBar:)`, `stop()` and
  `setTempoFactor()`.
  - Seeking schedules a file segment starting at the bar's sample frame.
  - The current position comes from the player node's sample time, not wall-clock time, so the
    judge follows the audio exactly.
  - It owns a click for the count-in and metronome.
- The input-to-output latency offset is measured once in a quick tap test and stored with the mic
  calibration.

**App (`PianoPad`)**

- A mode switch (Wait | Play-along), a tempo slider, a metronome toggle, and a bar and beat
  display.
- The playhead follows `BeatClock` (it reuses `location(atQuarter:)`, so the page view works
  unchanged).
- On `.rewind`: stop the audio, clear the held and expected state, briefly flash the failed bar,
  seek, count in, and resume.
- Grading: a take spans the rewinds. For the report, each bar is graded on its last attempt.

## Risks

- **The mic hears the backing.** With an acoustic piano and speakers, backing notes leak into
  detection. Recommend headphones, and in mic mode ignore detected pitches the backing is likely
  sounding (non-strict input already exists). An optional per-passage list of backing pitches per
  bar would make this better.
- **Latency.** Output buffer plus mic analysis adds tens of milliseconds. The windows absorb it,
  and the tap test removes the steady part.
- **Slow time stretching.** Below about 60% speed the audio gets smeary. We can cap the factor or
  add a "click only" option for very slow practice.

## Milestones

1. `BackingAnnotation`, `BeatClock` and `PlayAlongJudge`, with unit tests (on time, late, missed,
   wrong notes ignored, threshold, a mistake on a bar line, repeats, tempo factor).
2. `BackingPlayer`: play, seek to a bar, tempo factor, count-in click. Checked by ear on one
   passage.
3. PianoPad Play-along mode wired up with the rewind loop (MIDI keyboard first).
4. Mic support: wider windows, ignoring backing pitches, latency tap test.
5. Grading on each bar's last attempt, and a summary of rewinds per bar.

## Realtime safety (as built)

Code of ours that runs on a realtime thread, and what it may do:

| Thread | Our code | What it does |
| --- | --- | --- |
| CoreMIDI read thread | `MIDIInput.read` | Decodes packets on the stack, `post`s each note into a lock-free ring |
| Audio I/O thread (mic) | `AudioInput`'s sink block | Copies channel 0 into a preallocated `SPSCRing<Float>`, posts the block's length and host time |
| Audio render thread (playback) | none | `BackingPlayer` schedules everything ahead from the main thread, with no completion handlers |

The realtime code never allocates, takes a lock, sends an Objective-C message, dispatches
or touches a reference count. The closures capture only `SPSCRing` and
`RealtimeEventQueue.Poster`, which are plain structs of raw pointers. Waking the worker
thread is a `DispatchSemaphore.signal()` on an unretained reference, the standard
low-cost way to wake another thread from an audio or MIDI callback.

Everything else runs off the realtime threads: the worker threads, the detector queue,
and the main thread (`PlayAlongJudge`, the 60 Hz tick, the UI). `PlayAlongJudge` doesn't
allocate after `init` either, so it could move onto a realtime thread later if needed.

Positions come from the host clock (`PlaybackAnchor`), not from reading render-thread
state. The anchor includes the output's presentation latency.

### Still to tune by ear
- Time-pitch adds a little latency of its own, so the backing may sound a few ms after the
  clicks. Measure it and subtract it from the anchor if it's audible.
- The judge runs 40 ms (MIDI) or 150 ms (mic) behind the music, to allow for notes still
  on their way to the main thread.
- The `grade listen` CLI's `LiveRecorder` still locks and prints on the MIDI thread. It isn't
  used by play-along; move it to `RealtimeEventQueue` too.

## Backing-track library (Backing Tracks tab)

You can import and annotate backing tracks in the app instead of writing JSON by hand.

- **Import** an audio file. Nothing about it is changed. A metadata file is saved to
  `~/Library/Application Support/PianoPad/Backing Tracks/tracks/<id>.backing.json`
  with the audio's path, the trim start and end, bar 1, the tempo in quarter notes per
  minute, the time signature, the key and the count-in.
- **Waveform:** an overview of the whole file, plus a zoomable detail view with the bar grid
  drawn from bar 1. Drag the grey trim handles or the blue bar 1 line, or click to place the
  cursor. "Play from cursor" or "Play from bar 1" plays with a click on the bar grid. Stop
  playback on a downbeat to put the cursor there, then use "Set at cursor".
- **Tempo:** type it, tap it, or use "Bar N starts at the cursor" to compute it exactly over
  many bars.
- **Linking:** in Practice > Play along, the waveform menu links a saved track to the open
  passage (`passage:<book pdf>#<id>`) or MIDI file (`file:<path>`). Links are stored in
  `links.json` next to the tracks. A linked track takes priority over a `backing` entry in
  the book's annotations.
- **At play time**, bar 1 of the track is beat 0 of the reference MIDI. Replays seek to
  `bar1Seconds + (bar − 1) × bar length`, and playback stays within the trim.
- If the audio file has moved, the app also looks for a file with the same name in the
  library folder.
