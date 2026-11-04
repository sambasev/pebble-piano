#!/usr/bin/env python3
"""
Computer Use Test Harness for Pebble Piano.
Manages isolated sandboxed execution, process lifecycle, native driver dispatch,
screenshot capture, visual/state oracles, and test report generation.
"""

import os
import sys
import time
import json
import uuid
import shutil
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any, List

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DRIVER_BIN = REPO_ROOT / "scripts" / "cu" / "driver"
APP_BIN = REPO_ROOT / ".build" / "debug" / "PebblePiano"
DEFAULT_RUNS_DIR = REPO_ROOT / "test-runs"


class CUHarness:
    def __init__(self, run_id: Optional[str] = None, preseed_learner: Optional[str] = None):
        self.run_id = run_id or f"run_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
        self.run_dir = DEFAULT_RUNS_DIR / self.run_id
        self.screenshots_dir = self.run_dir / "screenshots"
        self.sandbox_dir = Path(f"/tmp/pebblepiano_cu_{uuid.uuid4().hex[:8]}")
        self.preseed_learner = preseed_learner
        self.app_process: Optional[subprocess.Popen] = None
        self.timeline: List[Dict[str, Any]] = []
        self.step_counter = 0

    def setup(self):
        """Prepares isolated directories and builds driver/app if needed."""
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.screenshots_dir.mkdir(parents=True, exist_ok=True)
        self.sandbox_dir.mkdir(parents=True, exist_ok=True)

        if not DRIVER_BIN.exists():
            print("Compiling driver.swift...")
            subprocess.run(["swiftc", "-O", str(REPO_ROOT / "scripts" / "cu" / "driver.swift"), "-o", str(DRIVER_BIN)], check=True)

        if not APP_BIN.exists():
            print("Building PianoPad binary...")
            subprocess.run(["swift", "build", "--product", "PebblePiano"], cwd=str(REPO_ROOT), check=True)

        if self.preseed_learner:
            self._create_preseeded_learner(self.preseed_learner)

    def _create_preseeded_learner(self, name: str):
        """Creates an initial learner in the sandbox store so launch skips onboarding."""
        self.sandbox_dir.mkdir(parents=True, exist_ok=True)
        learner_id = str(uuid.uuid4())
        learner_data = {
            "version": 1,
            "learners": [
                {
                    "id": learner_id,
                    "name": name,
                    "avatar": "pianokeys",
                    "kind": "adult",
                    "level": "beginner"
                }
            ]
        }
        with open(self.sandbox_dir / "learners.json", "w") as f:
            json.dump(learner_data, f, indent=2)

        # Create settings
        learner_folder = self.sandbox_dir / "Learners" / learner_id
        learner_folder.mkdir(parents=True, exist_ok=True)
        settings_data = {
            "persona": "alex",
            "inputSource": "computerKeyboard",
            "goalSong": "mary-had-a-little-lamb"
        }
        with open(learner_folder / "settings.json", "w") as f:
            json.dump(settings_data, f, indent=2)

        # Set active learner in preview UserDefaults
        subprocess.run([
            "defaults", "write", "PebblePiano.preview",
            "PianoPad.activeLearner", learner_id
        ], check=False)

    def launch_app(self, timeout_sec: float = 12.0) -> bool:
        """Launches PianoPad isolated to the sandbox directory."""
        # Ensure no old process is running
        subprocess.run(["pkill", "-x", "PebblePiano"], stderr=subprocess.DEVNULL)
        time.sleep(0.5)

        env = os.environ.copy()
        env["PEBBLEPIANO_PREVIEW_DATA"] = str(self.sandbox_dir)
        log_file = open(self.run_dir / "app.log", "w")

        self.app_process = subprocess.Popen(
            [str(APP_BIN)],
            cwd=str(REPO_ROOT),
            env=env,
            stdout=log_file,
            stderr=subprocess.STDOUT
        )

        start = time.time()
        while time.time() - start < timeout_sec:
            res = self.run_driver(["--find-window"])
            if res.get("id"):
                time.sleep(1.0)
                # Position window standardly
                self.run_driver(["--set-geometry", "100", "100", "1200", "750"])
                self.log_event("launch", "App launched and window positioned", {"window_id": res["id"]})
                self.capture_screenshot("launch_ready")
                return True
            time.sleep(0.5)

        self.log_event("launch_failure", f"Timed out waiting for app window ({timeout_sec}s)")
        return False

    def teardown(self):
        """Terminates app process and saves run report."""
        if self.app_process:
            self.app_process.terminate()
            try:
                self.app_process.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                self.app_process.kill()
            self.app_process = None

        subprocess.run(["pkill", "-x", "PebblePiano"], stderr=subprocess.DEVNULL)

        # Save timeline JSON
        with open(self.run_dir / "timeline.json", "w") as f:
            json.dump(self.timeline, f, indent=2)

        # Generate HTML report
        self._generate_html_report()

        # Clean sandbox
        if self.sandbox_dir.exists():
            shutil.rmtree(self.sandbox_dir, ignore_errors=True)

    def run_driver(self, args: List[str]) -> Dict[str, Any]:
        """Runs driver CLI and returns parsed JSON output."""
        proc = subprocess.run([str(DRIVER_BIN)] + args, capture_output=True, text=True)
        out = proc.stdout.strip()
        if not out:
            return {"exit_code": proc.returncode, "stderr": proc.stderr}
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return {"raw_output": out, "exit_code": proc.returncode}

    def capture_screenshot(self, label: str) -> Path:
        self.step_counter += 1
        filename = f"{self.step_counter:03d}_{label}.png"
        target_path = self.screenshots_dir / filename
        self.run_driver(["--capture", str(target_path)])
        self.log_event("screenshot", label, {"file": filename})
        return target_path

    def click_button(self, name: str) -> bool:
        res = self.run_driver(["--click-button", name])
        ok = res.get("success", False)
        self.log_event("click_button", f"Click '{name}'", {"success": ok})
        time.sleep(0.3)
        return ok

    def set_text(self, text: str) -> bool:
        res = self.run_driver(["--set-text", text])
        ok = res.get("success", False)
        self.log_event("set_text", f"Set text '{text}'", {"success": ok})
        time.sleep(0.3)
        return ok

    def send_key(self, name: str, duration_ms: int = 100) -> bool:
        res = self.run_driver(["--key", name, str(duration_ms)])
        ok = res.get("success", False)
        self.log_event("key", f"Key '{name}' ({duration_ms}ms)", {"success": ok})
        time.sleep(0.15)
        return ok

    def click_piano_key(self, pitch: int, duration_ms: int = 200) -> bool:
        res = self.run_driver(["--click-piano-key", str(pitch), str(duration_ms)])
        ok = res.get("success", False)
        self.log_event("piano_key", f"Pitch {pitch} ({duration_ms}ms)", {"success": ok})
        time.sleep(0.15)
        return ok

    def dump_ax(self) -> Dict[str, Any]:
        return self.run_driver(["--dump-ax"])

    def find_text_in_ax(self, needle: str, tree: Optional[Dict[str, Any]] = None) -> bool:
        if tree is None:
            tree = self.dump_ax()
        needle = needle.lower()
        queue = [tree]
        while queue:
            node = queue.pop(0)
            for key in ["title", "description", "value"]:
                val = str(node.get(key, "")).lower()
                if needle in val:
                    return True
            for child in node.get("children", []):
                queue.append(child)
        return False

    def log_event(self, action: str, description: str, metadata: Optional[Dict[str, Any]] = None):
        entry = {
            "step": self.step_counter,
            "timestamp": time.time(),
            "action": action,
            "description": description,
            "metadata": metadata or {}
        }
        self.timeline.append(entry)

    def _generate_html_report(self):
        shots = sorted(list(self.screenshots_dir.glob("*.png")))
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Pebble Piano Computer Use Test: {self.run_id}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 24px; background: #f6f8fa; color: #24292f; }}
        h1 {{ font-size: 22px; }}
        .meta {{ background: #fff; padding: 16px; border-radius: 8px; border: 1px solid #d0d7de; margin-bottom: 24px; }}
        .timeline {{ margin-top: 16px; }}
        .step {{ background: #fff; padding: 12px 16px; border-radius: 6px; border: 1px solid #d0d7de; margin-bottom: 12px; }}
        .action {{ font-weight: 600; color: #0969da; }}
        .screenshot {{ max-width: 700px; border: 1px solid #ccc; border-radius: 4px; margin-top: 8px; display: block; }}
    </style>
</head>
<body>
    <h1>Run Report: {self.run_id}</h1>
    <div class="meta">
        <strong>Total Steps:</strong> {len(self.timeline)}<br/>
        <strong>Screenshots:</strong> {len(shots)}<br/>
    </div>
    <h2>Timeline & Visual Evidence</h2>
    <div class="timeline">
"""
        for item in self.timeline:
            shot_html = ""
            if item.get("action") == "screenshot":
                filename = item.get("metadata", {}).get("file")
                if filename:
                    shot_html = f'<img class="screenshot" src="screenshots/{filename}" />'
            html += f"""
        <div class="step">
            <span class="action">[{item['action'].upper()}]</span> {item['description']}
            {shot_html}
        </div>
"""
        html += """
    </div>
</body>
</html>
"""
        with open(self.run_dir / "report.html", "w") as f:
            f.write(html)


if __name__ == "__main__":
    harness = CUHarness()
    harness.setup()
    print(f"Harness initialized for run: {harness.run_id}")
    if harness.launch_app():
        print("PianoPad launched successfully in isolated sandbox!")
        harness.capture_screenshot("initial_window")
        time.sleep(1)
    else:
        print("Failed to launch PianoPad")
    harness.teardown()
    print(f"Report written to: {harness.run_dir / 'report.html'}")
