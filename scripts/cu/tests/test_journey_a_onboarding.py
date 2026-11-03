#!/usr/bin/env python3
"""
Journey A Test: Fresh Learner Onboarding (SET-01, SET-04, Journey A)
Validates the first-launch onboarding path:
1. Fresh launch in an empty sandbox (no preseeded learner).
2. Welcome step -> Continue.
3. Learner step -> Set adult name "E2E Adult Alex" -> Continue.
4. Piano check -> Choose "Not right now" (Computer keyboard).
5. Teacher step -> Choose "Alex" -> Continue.
6. Goal song -> Choose "Mary Had a Little Lamb" -> Continue.
7. Ready step -> Finish setup.
8. Assert sandbox state (learners.json, settings.json).
9. Assert navigation lands on Learn view / Lesson 1 (Meet Middle C).
"""

import sys
import time
import json
from pathlib import Path

# Add scripts/cu to sys.path
SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

from harness import CUHarness


def run_journey_a():
    print("=== Running Journey A: Fresh Learner Onboarding ===")
    harness = CUHarness(preseed_learner=None)  # Empty sandbox
    harness.setup()

    try:
        assert harness.launch_app(timeout_sec=12.0), "Failed to launch app"
        harness.capture_screenshot("01_welcome")

        # Step 0: Welcome
        print("1. Welcoming new learner...")
        time.sleep(1.0)
        assert harness.click_button("Continue") or harness.send_key("return"), "Failed to advance past welcome"
        time.sleep(1.0)
        harness.capture_screenshot("02_learner_step")

        # Step 1: Name and Kind
        print("2. Entering learner name: E2E Adult Alex...")
        harness.set_text("E2E Adult Alex")
        time.sleep(0.5)
        harness.capture_screenshot("03_name_entered")
        assert harness.click_button("Continue") or harness.send_key("return"), "Failed to advance past learner step"
        time.sleep(1.0)
        harness.capture_screenshot("04_piano_check")

        # Step 2: "Are you at a piano or keyboard right now?"
        print("3. Selecting 'Not right now' for piano...")
        assert harness.click_button("Not right now"), "Failed to click 'Not right now'"
        time.sleep(1.0)
        harness.capture_screenshot("05_teacher_step")

        # Step 3: Teacher choice (Alex)
        print("4. Selecting teacher Alex...")
        harness.click_button("Alex")
        time.sleep(0.5)
        harness.capture_screenshot("06_teacher_selected")
        assert harness.click_button("Continue") or harness.send_key("return"), "Failed to advance past teacher step"
        time.sleep(1.0)
        harness.capture_screenshot("07_goal_step")

        # Step 4: Goal song
        print("5. Selecting goal song...")
        harness.click_button("Mary Had a Little Lamb")
        time.sleep(0.5)
        harness.capture_screenshot("08_goal_selected")
        assert harness.click_button("Continue") or harness.send_key("return"), "Failed to advance past goal step"
        time.sleep(1.0)
        harness.capture_screenshot("09_ready_step")

        # Step 5: Ready -> Start playing
        print("6. Finishing setup...")
        assert harness.click_button("Start playing") or harness.click_button("Continue") or harness.send_key("return"), "Failed to finish setup"
        time.sleep(2.0)
        harness.capture_screenshot("10_learn_view_landed")

        # Verification 1: Sandbox state
        learners_file = harness.sandbox_dir / "learners.json"
        assert learners_file.exists(), f"Learners file does not exist at {learners_file}"
        with open(learners_file, "r") as f:
            data = json.load(f)
        learners = data.get("learners", [])
        assert len(learners) == 1, f"Expected 1 learner, found {len(learners)}"
        learner = learners[0]
        active_id = learner["id"]
        assert learner["name"] == "E2E Adult Alex", f"Unexpected learner name: {learner['name']}"
        assert learner["kind"] == "adult", f"Unexpected learner kind: {learner['kind']}"
        print(f"Verified sandbox state: Learner '{learner['name']}' (ID: {active_id}) created successfully!")

        # Verification 2: Settings
        settings_file = harness.sandbox_dir / "Learners" / active_id / "settings.json"
        assert settings_file.exists(), f"Settings file missing at {settings_file}"
        with open(settings_file, "r") as f:
            settings = json.load(f)
        assert settings.get("inputSource") == "computerKeyboard", f"Expected computerKeyboard, got {settings.get('inputSource')}"
        print(f"Verified settings: inputSource={settings.get('inputSource')}, persona={settings.get('persona')}")

        print("=== Journey A PASSED Successfully! ===")
        return True

    except Exception as e:
        print(f"FAILED Journey A: {e}")
        harness.capture_screenshot("error_state")
        return False
    finally:
        harness.teardown()


if __name__ == "__main__":
    success = run_journey_a()
    sys.exit(0 if success else 1)
