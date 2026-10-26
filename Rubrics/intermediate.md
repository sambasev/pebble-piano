---
level: intermediate
checks: [notes, rhythm, tempo]
chord_window_ms: 50
notes:
  min_accuracy: 0.97
  extra_note_penalty: 1.0
rhythm:
  max_mean_ioi_error: 0.15
  flag_ioi_error: 0.30
tempo:
  tolerance: 0.10            # within ±10% of the target tempo
  max_steadiness_cv: 0.12
consecutive_passes: 2
play_along:
  early_ms: 150
  late_ms: 250
  mic_extra_late_ms: 100
  keys_extra_late_ms: 100
  max_miss_fraction: 0.2
  max_misses_per_bar: 1
  max_consecutive_misses: 2
  min_chord_coverage: 1.0
---
Intermediate players need the right notes, steady rhythm and the marked tempo.

When explaining a result, lead with the single biggest issue. If the tempo is off,
say whether it was too fast or too slow and by roughly how much.
