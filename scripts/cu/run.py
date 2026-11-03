#!/usr/bin/env python3
"""
Master Test Runner for PerfectPiano Computer Use Testing.

Usage:
  python3 scripts/cu/run.py --check          # Pass 0: Baseline & capability check
  python3 scripts/cu/run.py --journey-a      # Journey A: Fresh learner onboarding
  python3 scripts/cu/run.py --grd            # Journey B: GRD-01 to GRD-06 note grading
  python3 scripts/cu/run.py --smoke          # Pass 1: Primary Smoke (Journeys A & B)
  python3 scripts/cu/run.py --all            # Run all available test suites
"""

import sys
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
TESTS_DIR = SCRIPT_DIR / "tests"


def run_check():
    print("=== Running Pass 0: Baseline & Capability Check ===")
    driver = SCRIPT_DIR / "driver"
    if not driver.exists():
        print("Compiling driver...")
        subprocess.run(["swiftc", "-O", str(SCRIPT_DIR / "driver.swift"), "-o", str(driver)], check=True)
    res = subprocess.run([str(driver), "--check-environment"], capture_output=True, text=True)
    print(res.stdout)
    return res.returncode == 0


def run_journey_a():
    test_script = TESTS_DIR / "test_journey_a_onboarding.py"
    res = subprocess.run([sys.executable, str(test_script)])
    return res.returncode == 0


def run_journey_b():
    test_script = TESTS_DIR / "test_journey_b_grd.py"
    res = subprocess.run([sys.executable, str(test_script)])
    return res.returncode == 0


def main():
    args = sys.argv[1:]
    if not args or "--help" in args:
        print(__doc__)
        return

    success = True
    if "--check" in args:
        success = run_check()
    elif "--journey-a" in args:
        success = run_journey_a()
    elif "--grd" in args:
        success = run_journey_b()
    elif "--smoke" in args or "--all" in args:
        print("\n==========================================")
        print("   PERFECTPIANO COMPUTER USE TEST SUITE   ")
        print("==========================================\n")
        ok_a = run_journey_a()
        print("\n------------------------------------------\n")
        ok_b = run_journey_b()
        success = ok_a and ok_b
        print("\n==========================================")
        print(f"Overall Result: {'PASSED' if success else 'FAILED'}")
        print("==========================================\n")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
