---
level: beginner
checks: [notes, rhythm]
chord_window_ms: 50
notes:
  min_accuracy: 0.95
  extra_note_penalty: 0.5
rhythm:
  max_mean_ioi_error: 0.25   # mean interval error, as a share of the notated duration
  flag_ioi_error: 0.40       # flag any single interval off by more than this
tempo:                       # reported but not graded at this level
  tolerance: 0.15
  max_steadiness_cv: 0.20
consecutive_passes: 2
play_along:                  # play-along with a backing track: when to stop and replay a bar
  early_ms: 250              # a chord may be struck this early…
  late_ms: 400               # …or this late and still count
  mic_extra_late_ms: 120     # extra lateness allowed through the microphone
  keys_extra_late_ms: 150    # extra lateness for the computer keyboard (typing or clicking keys)
  max_miss_fraction: 0.34    # a bar fails when more than this share of its chords is missed…
  max_misses_per_bar: 2      # …capped at this many
  max_consecutive_misses: 3  # this many missed in a row always replays
  min_chord_coverage: 0.5    # share of a chord's notes that must be struck
---
Beginners pass on the right notes in the right order with roughly correct rhythm.
Tempo is reported but never held against them.

When explaining a result, praise what was correct first, then name at most one
note mistake and one rhythm issue per attempt, pointing to the measure and beat.
