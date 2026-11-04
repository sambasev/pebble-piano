"""Re-score this run's recorded replies with the current scorers (no model or judge calls).

Keeps every reply, latency and judge grade as recorded; only the deterministic findings change.
The as-run scoring is kept in report.as-run.md / summary.as-run.json.

    python3 evals/tutor/results/live-20261104/rescore.py
"""
import json
import os
import sys

DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(DIR, "..", "..")))
import cases as CS  # noqa: E402
import report  # noqa: E402
import scorers  # noqa: E402

by_id = {c["id"]: c for c in CS.CASES}
samples = [json.loads(line) for line in open(os.path.join(DIR, "samples.jsonl"))]
for s in samples:
    if s["output"] is None:
        continue
    case = by_id[s["id"]]
    facts = case["build"]().facts
    kept = [f for f in s["findings"] if f["rule"] == "tap_refused"]  # from the live chip tap, not re-derivable
    s["findings"] = [f.as_dict() for f in scorers.score(s["output"], case, facts)] + kept
    # A chip tap's own findings stay as recorded: its actions and chips weren't saved.
meta = json.load(open(os.path.join(DIR, "summary.as-run.json")))["meta"]
meta["title"] = "live (re-scored after triage)"
summary = report.summarize(samples)
with open(os.path.join(DIR, "samples.jsonl"), "w") as f:
    for s in samples:
        f.write(json.dumps(s) + "\n")
json.dump({"meta": meta, **summary}, open(os.path.join(DIR, "summary.json"), "w"), indent=1)
open(os.path.join(DIR, "report.md"), "w").write(report.markdown(summary, samples, meta))
m = summary["metrics"]
print(" · ".join(f"{k} {m[k]['rate']:.0%}" for k in ("overall", "task", "adherence", "grounding", "followups", "hallucination_rate")))
