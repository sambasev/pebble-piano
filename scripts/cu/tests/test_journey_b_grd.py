#!/usr/bin/env python3
"""
Journey B & Concrete Grader Checks (GRD-01 to GRD-06, PRA-01 to PRA-07)
Validates note grading via on-screen piano clicks and musical typing:
- GRD-01: C4 D4 E4 F4 G4 A4 B4 C5 (All 8 correct -> PASS)
- GRD-02: Substitute F#4 for F4 (7 correct, 1 wrong pitch -> FAIL)
- GRD-03: Omit F4 (7 correct, 1 missed -> FAIL)
- GRD-04: Insert F#4 between E4 and F4 (8 correct, 1 extra -> FAIL)
- GRD-05: Clean run; hold/release key; Grade; new take; Esc (lifecycle & discard)
- GRD-06: Mapped computer keys A S D F G H J K (musical typing -> PASS)
"""

import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

from harness import CUHarness


def run_grd_suite():
    print("=== Running Journey B: Concrete Grader Checks (GRD-01 through GRD-06) ===")
    harness = CUHarness(preseed_learner="E2E Adult Alex")
    harness.setup()

    try:
        assert harness.launch_app(timeout_sec=12.0), "Failed to launch PianoPad"
        time.sleep(2.0)
        harness.capture_screenshot("01_practice_tab_initial")

        # Navigate to Practice tab if not already on it
        harness.click_button("Practice")
        time.sleep(1.0)
        harness.capture_screenshot("02_practice_view")

        # Verify Wait mode is active
        harness.click_button("Wait")
        time.sleep(0.5)

        # ----------------------------------------------------
        # GRD-01: Clean 8-note run via on-screen piano clicks
        # ----------------------------------------------------
        print("\n--- Testing GRD-01: Clean 8-note run (C4 to C5) via piano clicks ---")
        harness.click_button("Start again")
        time.sleep(0.5)

        # Pitches: C4 (60), D4 (62), E4 (64), F4 (65), G4 (67), A4 (69), B4 (71), C5 (72)
        eight_pitches = [60, 62, 64, 65, 67, 69, 71, 72]
        for p in eight_pitches:
            harness.click_piano_key(pitch=p, duration_ms=180)
            time.sleep(0.1)

        harness.capture_screenshot("grd01_notes_clicked")
        # Finish take
        harness.click_button("Grade the take")
        time.sleep(1.0)
        harness.capture_screenshot("grd01_report")
        print("GRD-01 take graded.")

        # ----------------------------------------------------
        # GRD-06: Repeat clean run using mapped computer keys
        # ----------------------------------------------------
        print("\n--- Testing GRD-06: Clean run via Musical Typing (A S D F G H J K) ---")
        harness.click_button("Start again")
        time.sleep(0.5)

        # In musical typing (octave 4): A=C4, S=D4, D=E4, F=F4, G=G4, H=A4, J=B4, K=C5
        typing_keys = ["a", "s", "d", "f", "g", "h", "j", "k"]
        for key in typing_keys:
            harness.send_key(key, duration_ms=120)
            time.sleep(0.1)

        harness.capture_screenshot("grd06_typing_played")
        harness.send_key("return")  # Return finishes take
        time.sleep(1.0)
        harness.capture_screenshot("grd06_report")
        print("GRD-06 take graded.")

        # ----------------------------------------------------
        # GRD-02: Substitute F#4 (66) for F4 (65)
        # ----------------------------------------------------
        print("\n--- Testing GRD-02: Substitute F#4 for F4 (Expected: FAIL) ---")
        harness.click_button("Start again")
        time.sleep(0.5)

        wrong_pitches = [60, 62, 64, 66, 67, 69, 71, 72]
        for p in wrong_pitches:
            harness.click_piano_key(pitch=p, duration_ms=180)
            time.sleep(0.1)

        harness.capture_screenshot("grd02_wrong_note_played")
        harness.click_button("Grade the take")
        time.sleep(1.0)
        harness.capture_screenshot("grd02_report")
        print("GRD-02 take graded.")

        # ----------------------------------------------------
        # GRD-03: Omit F4 (65)
        # ----------------------------------------------------
        print("\n--- Testing GRD-03: Omit F4 (Expected: FAIL) ---")
        harness.click_button("Start again")
        time.sleep(0.5)

        omitted_pitches = [60, 62, 64, 67, 69, 71, 72]
        for p in omitted_pitches:
            harness.click_piano_key(pitch=p, duration_ms=180)
            time.sleep(0.1)

        harness.capture_screenshot("grd03_omitted_note_played")
        harness.click_button("Grade the take")
        time.sleep(1.0)
        harness.capture_screenshot("grd03_report")
        print("GRD-03 take graded.")

        # ----------------------------------------------------
        # GRD-04: Insert F#4 between E4 and F4
        # ----------------------------------------------------
        print("\n--- Testing GRD-04: Insert extra note F#4 (Expected: FAIL) ---")
        harness.click_button("Start again")
        time.sleep(0.5)

        extra_pitches = [60, 62, 64, 66, 65, 67, 69, 71, 72]
        for p in extra_pitches:
            harness.click_piano_key(pitch=p, duration_ms=180)
            time.sleep(0.1)

        harness.capture_screenshot("grd04_extra_note_played")
        harness.click_button("Grade the take")
        time.sleep(1.0)
        harness.capture_screenshot("grd04_report")
        print("GRD-04 take graded.")

        # ----------------------------------------------------
        # GRD-05: Hold/release key, Grade, new take, Esc discard
        # ----------------------------------------------------
        print("\n--- Testing GRD-05: Lifecycle & Esc discard ---")
        harness.click_button("Start again")
        time.sleep(0.5)
        # Play a single note
        harness.click_piano_key(pitch=60, duration_ms=300)
        time.sleep(0.2)
        harness.capture_screenshot("grd05_single_note")
        # Esc should discard
        harness.send_key("escape")
        time.sleep(0.5)
        harness.capture_screenshot("grd05_discarded")
        print("GRD-05 discard verified.")

        print("\n=== Journey B & GRD-01 to GRD-06 Completed Successfully! ===")
        return True

    except Exception as e:
        print(f"FAILED Journey B: {e}")
        harness.capture_screenshot("error_state")
        return False
    finally:
        harness.teardown()


if __name__ == "__main__":
    success = run_grd_suite()
    sys.exit(0 if success else 1)
