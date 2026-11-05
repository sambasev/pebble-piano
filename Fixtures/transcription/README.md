# Audio-to-MIDI Transcription Benchmarks & Ground Truth

Drop real or synthetic recording test cases into this directory to evaluate them against any model or method.

## Test Case File Structure

Each test case consists of files sharing a common base name (`<case_name>`):

```
Fixtures/transcription/
├── <case_name>.wav          # [Required] Microphone audio recording (mono/stereo WAV, 44.1 or 48 kHz)
├── <case_name>.truth.mid    # [Required] Ground truth MIDI of what was actually played (e.g. from USB-MIDI)
├── <case_name>.guide.mid    # [Optional] The score being followed (if testing wait-mode / score tracking)
└── <case_name>.cal.wav      # [Optional] Calibration audio (quiet, C4, D4, E4) to test with piano profile
```

### Explanations:
1. **`<case_name>.wav`**: The audio recording of the piano.
2. **`<case_name>.truth.mid`**: The ground truth note events (pitches, exact onsets and offsets). For real piano takes, record the piano's USB-MIDI or MIDI Out simultaneously while recording the microphone.
3. **`<case_name>.guide.mid`**: The sheet music score that the pianist was trying to play.
   - If the pianist played cleanly with no mistakes: you can omit this file (or symlink to `.truth.mid`), and the evaluator will treat the score as matching the truth.
   - If the take contains mistakes (e.g., played a wrong key or hit an extra note): `.guide.mid` is the intended score, and `.truth.mid` reflects what was actually played. This allows measuring whether the score tracker correctly flags mistakes or falsely lets wrong notes pass.

## Running the Evaluation

To evaluate all test cases in this directory:
```sh
swift run grade eval
```

To evaluate a specific case:
```sh
swift run grade eval --case Fixtures/transcription/<case_name>
```

To evaluate custom directories elsewhere on your system:
```sh
swift run grade eval --fixtures /path/to/my/audio_takes
```

## Retrospective Bar-by-Bar Evaluation (ByteDance CRNN via Modal GPU)

See detailed benchmark findings, quantitative scorecard, and proofs in `docs/bytedance_retrospective_eval.md` and `docs/bytedance_retrospective_eval.json`.

To run or test the ByteDance GPU transcription service on Modal:
```sh
modal run scripts/bytedance_modal.py
```

Deployed endpoint: printed by `modal deploy scripts/bytedance_modal.py` (your own Modal account; not published here).
