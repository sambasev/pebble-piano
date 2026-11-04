#!/usr/bin/env python3
"""Pebble Piano tutor evals: follow-ups, instruction adherence, hallucination and latency.

  python3 evals/tutor/run.py live [--trials 3] [--only fu_,gr_] [--judge auto|claude|meta|none]
                                  [--baseline evals/tutor/baseline.json] [--workers 4]
      Calls the tutor (Muse Spark) with the app's real system prompt and schema
      (docs/tutor_contract.json) on realistic contexts built from the repo's fixtures. Needs
      MODEL_API_KEY (or the app's Keychain item). Writes evals/tutor/results/<stamp>/.

  python3 evals/tutor/run.py replay
      No network. Re-scores the tutor replies already recorded in docs/tutor_evaluation.json
      and docs/tutor_live_evaluation.json with these (stricter) scorers.

  python3 evals/tutor/run.py selftest
      No network. Checks the scorers against hand-labelled good and bad replies (goldens.py).

  python3 evals/tutor/run.py calibrate --judge claude
      Runs the LLM judge on the goldens and reports how often it agrees with the labels.

Exit status: 1 if a live run regresses against --baseline or misses the latency budget
(with --gate), so it can run in CI.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cases as CS  # noqa: E402
import client  # noqa: E402
import context as C  # noqa: E402
import report  # noqa: E402
import scorers  # noqa: E402
from goldens import GOLDENS  # noqa: E402
from judge import Judge  # noqa: E402

CONTRACT = CS.CONTRACT
SCHEMA = CONTRACT["schema"]


def system_for(case: Dict[str, Any]) -> str:
    return CONTRACT["instructions"]["child" if case.get("audience") == "child" else "adult"]


def run_case(case: Dict[str, Any], trial: int, key: str, model: str, judge: Judge) -> Dict[str, Any]:
    ctx = case["build"]()
    prompt = ctx.prompt()
    image = os.path.join(C.ROOT, ctx.page_image) if ctx.page_image else None
    msgs = client.messages(system_for(case), case.get("history", []), prompt, case["question"], image)
    res = client.chat(key, model, msgs, SCHEMA)
    sample = {"id": case["id"], "category": case["category"], "trial": trial, "question": case["question"],
              "output": res["output"], "error": res["error"], "latency": res["latency"], "usage": res["usage"],
              "findings": [], "context_chars": len(prompt)}
    if res["output"] is None:
        return sample
    sample["findings"] = [f.as_dict() for f in scorers.score(res["output"], case, ctx.facts)]
    sample["judge"] = judge.grade(case, prompt, res["output"])
    # Follow-up answerability: tap the first chip, as the learner would.
    chips = res["output"].get("suggestions") or []
    if case.get("tap_followup") and chips and res["output"].get("on_topic"):
        history = case.get("history", []) + [{"role": "user", "text": case["question"]},
                                             {"role": "assistant", "text": res["output"].get("reply", "")}]
        tap = client.chat(key, model, client.messages(system_for(case), history, prompt, chips[0], image), SCHEMA)
        out = tap["output"] or {}
        tap_case = {**case, "question": chips[0], "expect": {}}
        tap_findings = [f.as_dict() for f in scorers.score(out, tap_case, ctx.facts)] if out else []
        sample["tap"] = {"chip": chips[0], "answered": bool(out.get("on_topic")) and bool((out.get("reply") or "").strip()),
                         "reply": out.get("reply"), "latency": tap["latency"], "findings": tap_findings}
        if not sample["tap"]["answered"]:
            sample["findings"].append({"metric": "followups", "rule": "tap_refused", "hard": True,
                                       "message": f"tapping its own chip {chips[0]!r} was refused or empty"})
    return sample


def cmd_live(args) -> int:
    key = client.api_key()
    if not key:
        print("No MODEL_API_KEY (and no Keychain item). Set MODEL_API_KEY to run live.", file=sys.stderr)
        return 2
    judge = Judge.pick(args.judge, key)
    picked = [c for c in CS.CASES if not args.only or any(c["id"].startswith(p) for p in args.only.split(","))]
    jobs = [(c, t) for c in picked for t in range(1, args.trials + 1)]
    print(f"{len(picked)} cases × {args.trials} trials against {args.model}, judge {judge.backend}", file=sys.stderr)
    with ThreadPoolExecutor(args.workers) as pool:
        samples = list(pool.map(lambda j: run_case(j[0], j[1], key, args.model, judge), jobs))
    for s in samples:
        print(f"  {'PASS' if report.sample_passes(s) else 'FAIL'} {s['id']} #{s['trial']}", file=sys.stderr)
    return finish(samples, {"model": args.model, "mode": "live", "title": "live"}, args)


def finish(samples, meta, args) -> int:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    meta["date"] = stamp
    out_dir = args.out or os.path.join(HERE, "results", f"{meta['mode']}-{stamp}")
    os.makedirs(out_dir, exist_ok=True)
    summary = report.summarize(samples)
    with open(os.path.join(out_dir, "samples.jsonl"), "w") as f:
        for s in samples:
            f.write(json.dumps(s) + "\n")
    json.dump({"meta": meta, **summary}, open(os.path.join(out_dir, "summary.json"), "w"), indent=1)
    md = report.markdown(summary, samples, meta)
    open(os.path.join(out_dir, "report.md"), "w").write(md)
    m = summary["metrics"]
    print(f"\noverall {m['overall']['rate']:.0%} · task {m['task']['rate']:.0%} · adherence {m['adherence']['rate']:.0%} · "
          f"grounding {m['grounding']['rate']:.0%} · follow-ups {m['followups']['rate']:.0%} · "
          f"hallucination rate {m['hallucination_rate']['rate'] or 0:.0%}")
    if summary["latency"].get("total_s"):
        L = summary["latency"]
        tv = L.get("ttfv_s")
        print((f"latency p50/p90: first visible text {tv['p50']:.1f}/{tv['p90']:.1f}s, " if tv else "latency p50/p90: ")
              + f"full reply {L['total_s']['p50']:.1f}/{L['total_s']['p90']:.1f}s")
    print(f"report: {os.path.join(out_dir, 'report.md')}")
    status = 0
    if getattr(args, "baseline", None) and os.path.exists(args.baseline):
        problems = report.compare(summary, json.load(open(args.baseline)))
        for p in problems:
            print("REGRESSION:", p)
        status = 1 if problems and args.gate else 0
    if getattr(args, "gate", False) and any(b["ok"] is False for b in summary["latency_budget"].values()):
        print("Latency budget missed:", summary["latency_budget"])
        status = 1
    return status


# ----------------------------------------------------------------------------- replay

def _legacy_case(test: Dict[str, Any]) -> Dict[str, Any]:
    case = {"id": test["id"], "category": "legacy:" + test["category"], "question": test.get("question", ""),
            "audience": test.get("audience", "adult"), "expect": {}}
    if "expected_on_topic" in test:
        case["expect"]["on_topic"] = test["expected_on_topic"]
    return case


def _legacy_facts(ctx_text: str) -> C.Facts:
    f = C.Facts()
    m = re.search(r"(\d+) (?:bars|measures) total", ctx_text or "")
    if m:
        f.bar_count = int(m.group(1))
        f.two_hands = True  # unknown in these thin contexts: don't flag hand choices
    return f


def cmd_replay(args) -> int:
    sys.path.insert(0, os.path.join(C.ROOT, "scripts"))
    import evaluate_tutor as legacy  # the existing harness: its case definitions

    tests = {t["id"]: t for t in legacy.GUARDRAIL_TESTS + legacy.ADVERSARIAL_TESTS + legacy.PEDAGOGY_TESTS
             + legacy.MULTIMODAL_TESTS + legacy.ACTION_TESTS}
    recorded = json.load(open(os.path.join(C.ROOT, "docs", "tutor_evaluation.json")))
    samples: List[Dict[str, Any]] = []
    for r in recorded["results"]:
        test = tests.get(r["id"])
        if not test or not r.get("model_output"):
            continue
        case = _legacy_case(test)
        facts = _legacy_facts(test.get("context", ""))
        out = r["model_output"]
        samples.append({"id": r["id"], "category": case["category"], "question": case["question"], "output": out,
                        "error": None, "latency": {"total_s": r.get("latency_sec")}, "usage": {},
                        "findings": [f.as_dict() for f in scorers.score(out, case, facts)]})
    # The app end to end: text transcripts (actions are known only through "app:" lines).
    ode = C.score_block("ode")[1]
    live = json.load(open(os.path.join(C.ROOT, "docs", "tutor_live_evaluation.json")))
    for r in live:
        turns = r["transcript"]
        for i, line in enumerate(turns):
            if not line.startswith("tutor: "):
                continue
            question = next((t[len("learner: "):] for t in reversed(turns[:i]) if t.startswith("learner: ")), "")
            acted = i + 1 < len(turns) and turns[i + 1].startswith("app: ")
            child = r["scenario"] == "G" and r["id"] != "g3_grown_up"
            case = {"id": r["id"], "category": f"live:{r['scenario']}", "question": question, "text_only": True,
                    "acted": acted, "audience": "child" if child else "adult", "expect": {}}
            facts = ode if r["scenario"] in "AB" else C.Facts()
            out = {"on_topic": True, "reply": line[len("tutor: "):], "actions": [], "suggestions": []}
            samples.append({"id": r["id"], "category": case["category"], "question": question, "output": out, "error": None,
                            "latency": {"total_s": r.get("seconds")}, "usage": {},
                            "findings": [f.as_dict() for f in scorers.score(out, case, facts)]})
    note = ("Replay: no model calls. The tutor replies recorded in docs/tutor_evaluation.json (model-only, 31 checks) and "
            "docs/tutor_live_evaluation.json (the app end to end, text only) re-scored with these scorers. Latency is "
            "the recorded wall time of the original (non-streamed) call, so first-token numbers aren't available. "
            "Live transcripts have no chips or action objects, so follow-up and action checks don't apply to them.")
    return finish(samples, {"model": recorded["summary"].get("model", "muse-spark-1.3") if isinstance(recorded.get("summary"), dict) else "muse-spark-1.3",
                            "mode": "replay", "title": "replay of recorded tutor replies", "note": note}, args)


# ----------------------------------------------------------------------------- self-test & calibration

def cmd_selftest(args) -> int:
    by_id = CS.by_id()
    failures = 0
    for case_id, label, out, rule in GOLDENS:
        case = by_id[case_id]
        facts = case["build"]().facts
        found = scorers.score(out, case, facts)
        hard = {f"{f.metric}.{f.rule}" for f in found if f.hard}
        ok = (not hard) if rule is None else (rule in hard)
        failures += not ok
        print(f"{'ok ' if ok else 'BAD'} {case_id:22} {label:4} {'must pass' if rule is None else 'must catch ' + rule:40}"
              + ("" if ok else f" -> got {sorted(hard) or 'nothing'}"))
    # Every case's context builds and stays within the app's bounds.
    for c in CS.CASES:
        ctx = c["build"]()
        assert len(ctx.prompt()) < 40000, c["id"]
    print(f"\n{len(GOLDENS) - failures}/{len(GOLDENS)} goldens behave; {len(CS.CASES)} case contexts build.")
    return 1 if failures else 0


def cmd_calibrate(args) -> int:
    judge = Judge.pick(args.judge, client.api_key())
    if judge.backend == "none":
        print("No judge backend available (set ANTHROPIC_API_KEY or MODEL_API_KEY).", file=sys.stderr)
        return 2
    by_id = CS.by_id()
    agree = total = 0
    for case_id, label, out, rule in GOLDENS:
        if not out.get("on_topic"):
            continue
        case = by_id[case_id]
        g = judge.grade(case, case["build"]().prompt(), out)
        if not g or "error" in g:
            print("judge error", case_id, g)
            continue
        verdict = "good" if min(g["grounding"], g["helpfulness"]) >= 4 else "bad"
        total += 1
        agree += verdict == label
        print(f"{'agree   ' if verdict == label else 'DISAGREE'} {case_id:22} label {label:4} judge {verdict} "
              f"(ground {g['grounding']}, help {g['helpfulness']}) {g['unsupported_claims'][:2]}")
    print(f"\nJudge agrees with the labels on {agree}/{total}.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=["live", "replay", "selftest", "calibrate"])
    p.add_argument("--model", default=os.environ.get("TUTOR_MODEL", "muse-spark-1.3"))
    p.add_argument("--trials", type=int, default=3)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--only", help="comma-separated case id prefixes")
    p.add_argument("--judge", default="auto", choices=["auto", "claude", "meta", "none"])
    p.add_argument("--baseline", help="summary.json of an earlier run to compare against")
    p.add_argument("--gate", action="store_true", help="exit 1 on regression or a missed latency budget")
    p.add_argument("--out", help="output directory")
    args = p.parse_args()
    return {"live": cmd_live, "replay": cmd_replay, "selftest": cmd_selftest, "calibrate": cmd_calibrate}[args.mode](args)


if __name__ == "__main__":
    sys.exit(main())
