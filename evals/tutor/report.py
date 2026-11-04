"""Aggregates scored samples into metrics, a Markdown report and a baseline comparison."""
from __future__ import annotations

import math
import statistics
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional

METRICS = ["task", "adherence", "grounding", "followups"]
LATENCY_BUDGET = {"ttfv_s": 4.0, "total_s": 10.0}  # p90 targets, seconds


def wilson(k: int, n: int, z: float = 1.96):
    if n == 0:
        return (None, None)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def pct(values: List[float], q: float) -> Optional[float]:
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    k = (len(v) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def sample_passes(s: Dict[str, Any], metric: Optional[str] = None) -> bool:
    if s.get("error"):
        return False
    return not any(f["hard"] and (metric is None or f["metric"] == metric) for f in s["findings"])


def summarize(samples: List[Dict[str, Any]]) -> Dict[str, Any]:
    n = len(samples)
    out: Dict[str, Any] = {"samples": n, "cases": len({s["id"] for s in samples}), "metrics": {}, "by_category": {},
                           "rules": {}, "latency": {}, "judge": {}, "errors": sum(1 for s in samples if s.get("error"))}
    for m in METRICS + [None]:
        k = sum(sample_passes(s, m) for s in samples)
        lo, hi = wilson(k, n)
        out["metrics"][m or "overall"] = {"pass": k, "n": n, "rate": k / n if n else None, "ci95": [lo, hi]}
    # Hallucination rate = share of answered samples with any hard grounding finding.
    answered = [s for s in samples if not s.get("error") and (s.get("output") or {}).get("on_topic")]
    hk = sum(1 for s in answered if not sample_passes(s, "grounding"))
    out["metrics"]["hallucination_rate"] = {"bad": hk, "n": len(answered), "rate": hk / len(answered) if answered else None,
                                            "ci95": list(wilson(hk, len(answered)))}
    with_chips = [s for s in answered if s.get("output", {}).get("suggestions")]
    out["metrics"]["followup_coverage"] = {"n": len(answered), "rate": len(with_chips) / len(answered) if answered else None}
    taps = [s["tap"] for s in samples if s.get("tap")]
    if taps:
        ok = sum(1 for t in taps if t["answered"])
        out["metrics"]["followup_answerable"] = {"pass": ok, "n": len(taps), "rate": ok / len(taps), "ci95": list(wilson(ok, len(taps)))}
    cats = defaultdict(list)
    for s in samples:
        cats[s["category"]].append(s)
    for cat, ss in sorted(cats.items()):
        out["by_category"][cat] = {"n": len(ss), "overall": sum(sample_passes(s) for s in ss) / len(ss)}
    rules = Counter((f["metric"], f["rule"], f["hard"]) for s in samples for f in s["findings"])
    out["rules"] = {f"{m}.{r}{'' if h else ' (soft)'}": c for (m, r, h), c in rules.most_common()}
    # Consistency: a case passes only if every trial passed (pass^k).
    by_case = defaultdict(list)
    for s in samples:
        by_case[s["id"]].append(sample_passes(s))
    trials = max((len(v) for v in by_case.values()), default=0)
    out["consistency"] = {"trials": trials, "all_trials_pass": sum(all(v) for v in by_case.values()),
                          "flaky": sorted(k for k, v in by_case.items() if any(v) and not all(v)),
                          "cases": len(by_case)}
    for key in ("ttft_s", "ttfv_s", "total_s", "tokens_per_s"):
        vals = [(s.get("latency") or {}).get(key) for s in samples]
        vals = [v for v in vals if v is not None]
        if vals:
            out["latency"][key] = {"n": len(vals), "mean": statistics.mean(vals), "p50": pct(vals, .5),
                                   "p90": pct(vals, .9), "p95": pct(vals, .95), "max": max(vals)}
    toks = [s.get("usage", {}) for s in samples]
    if any(t.get("output") for t in toks):
        out["usage"] = {"input_mean": statistics.mean([t["input"] for t in toks if t.get("input")] or [0]),
                        "output_mean": statistics.mean([t["output"] for t in toks if t.get("output")] or [0])}
    grades = [s["judge"] for s in samples if s.get("judge") and "error" not in s["judge"]]
    if grades:
        for dim in ("grounding", "helpfulness", "teaching", "followups"):
            out["judge"][dim] = statistics.mean(g[dim] for g in grades)
        out["judge"]["n"] = len(grades)
        out["judge"]["with_unsupported_claims"] = sum(1 for g in grades if g["unsupported_claims"]) / len(grades)
        out["judge"]["model"] = grades[0].get("judge")
    out["judge_errors"] = sum(1 for s in samples if s.get("judge") and "error" in s["judge"])
    budget = {}
    for key, limit in LATENCY_BUDGET.items():
        p90 = out["latency"].get(key, {}).get("p90")
        budget[key] = {"p90": p90, "limit": limit, "ok": None if p90 is None else p90 <= limit}
    out["latency_budget"] = budget
    return out


def compare(now: Dict[str, Any], base: Dict[str, Any]) -> List[str]:
    """Regressions: a metric whose rate fell below the baseline's 95% interval, or latency p90 up >25%."""
    problems = []
    for m, v in now["metrics"].items():
        b = base.get("metrics", {}).get(m)
        if not b or v.get("rate") is None or b.get("rate") is None:
            continue
        if m == "hallucination_rate":
            if b.get("ci95", [None, None])[1] is not None and v["rate"] > b["ci95"][1]:
                problems.append(f"{m} rose {b['rate']:.0%} → {v['rate']:.0%}")
        elif b.get("ci95", [None])[0] is not None and v["rate"] < b["ci95"][0]:
            problems.append(f"{m} fell {b['rate']:.0%} → {v['rate']:.0%}")
    for key in ("ttfv_s", "total_s"):
        a, b = now["latency"].get(key, {}).get("p90"), base.get("latency", {}).get(key, {}).get("p90")
        if a and b and a > b * 1.25:
            problems.append(f"{key} p90 slowed {b:.1f}s → {a:.1f}s")
    return problems


def _rate(m: Dict[str, Any]) -> str:
    if m.get("rate") is None:
        return "–"
    lo, hi = m.get("ci95", [None, None])
    ci = f" ({lo:.0%}–{hi:.0%})" if lo is not None else ""
    return f"{m['rate']:.0%}{ci}"


def markdown(summary: Dict[str, Any], samples: List[Dict[str, Any]], meta: Dict[str, Any]) -> str:
    s = summary
    L = [f"# Tutor eval: {meta.get('title', 'run')}", "",
         f"Model `{meta.get('model')}` · mode `{meta.get('mode')}` · {meta.get('date')} · "
         f"{s['cases']} cases × {s['consistency']['trials']} trials = {s['samples']} samples"
         + (f" · judge `{s['judge'].get('model')}`" if s.get("judge") else " · no LLM judge"), ""]
    if meta.get("note"):
        L += [meta["note"], ""]
    L += ["## Scorecard", "", "| Metric | Result (95% CI) | What it measures |", "|---|---|---|"]
    explain = {
        "overall": "No hard failure on any metric",
        "task": "Did what this case asks (right action, refusal, key fact)",
        "adherence": "Follows the system prompt: JSON, ≤100 words, no unasked numbers, honest tense, action rules",
        "grounding": "No claim the context contradicts (bars, notes, grades, dates, memory)",
        "followups": "Chips: ≤3, ≤60 chars, learner's voice, not echoes, possible in the app",
        "hallucination_rate": "Answered replies with ≥1 unsupported claim (lower is better)",
        "followup_coverage": "Answered replies that offer chips",
        "followup_answerable": "Tapping the first chip gets an on-topic answer",
    }
    for key in ["overall", "task", "adherence", "grounding", "followups", "hallucination_rate", "followup_coverage", "followup_answerable"]:
        if key in s["metrics"]:
            L.append(f"| **{key}** | {_rate(s['metrics'][key])} | {explain[key]} |")
    c = s["consistency"]
    L += ["", f"Consistency: {c['all_trials_pass']}/{c['cases']} cases pass every trial"
          + (f"; flaky: {', '.join(c['flaky'])}" if c["flaky"] else "") + "."]
    if s.get("judge"):
        j = s["judge"]
        L += ["", "### LLM judge (1–5)", "", "| Grounding | Helpfulness | Teaching | Follow-ups | Replies with unsupported claims |",
              "|---|---|---|---|---|",
              f"| {j['grounding']:.2f} | {j['helpfulness']:.2f} | {j['teaching']:.2f} | {j['followups']:.2f} | {j['with_unsupported_claims']:.0%} |"]
    if s["latency"]:
        L += ["", "### Latency (seconds)", "", "| | n | p50 | p90 | p95 | max | p90 budget |", "|---|---|---|---|---|---|---|"]
        names = {"ttft_s": "First token", "ttfv_s": "First visible text", "total_s": "Full reply", "tokens_per_s": "Output tokens/s"}
        for key, v in s["latency"].items():
            b = s["latency_budget"].get(key)
            mark = "" if not b or b["ok"] is None else (f"≤ {b['limit']:g}s ✅" if b["ok"] else f"≤ {b['limit']:g}s ❌")
            L.append(f"| {names[key]} | {v['n']} | {v['p50']:.2f} | {v['p90']:.2f} | {v['p95']:.2f} | {v['max']:.2f} | {mark} |")
    L += ["", "## By category", "", "| Category | Samples | Pass |", "|---|---|---|"]
    for cat, v in s["by_category"].items():
        L.append(f"| {cat} | {v['n']} | {v['overall']:.0%} |")
    if s["rules"]:
        L += ["", "## Failures by rule", "", "| Rule | Count |", "|---|---|"]
        L += [f"| `{r}` | {n} |" for r, n in s["rules"].items()]
    L += ["", "## Cases", "", "| Case | Category | Pass | Latency | Findings |", "|---|---|---|---|---|"]
    for smp in samples:
        lat = (smp.get("latency") or {}).get("total_s")
        fs = "; ".join(("" if f["hard"] else "(soft) ") + f"{f['metric']}.{f['rule']}: {f['message']}" for f in smp["findings"])
        if smp.get("error"):
            fs = f"ERROR {smp['error']}"
        fs = fs.replace("|", "\\|").replace("\n", " ")
        L.append(f"| `{smp['id']}`{' #' + str(smp['trial']) if smp.get('trial') else ''} | {smp['category']} | "
                 f"{'✅' if sample_passes(smp) else '❌'} | {'' if lat is None else f'{lat:.1f}s'} | {fs or 'OK'} |")
    bad = [x for x in samples if not sample_passes(x) and x.get("output")]
    if bad:
        L += ["", "## Failing replies", ""]
        for smp in bad[:30]:
            o = smp["output"]
            L += [f"### `{smp['id']}`", "", f"- **Question:** {smp.get('question', '')[:200]}",
                  f"- **Reply:** {(o.get('reply') or '').strip()[:600]!r}",
                  f"- **Actions:** {[a.get('kind') for a in o.get('actions') or []]} · **Chips:** {o.get('suggestions')}"]
            for f in smp["findings"]:
                if f["hard"]:
                    L.append(f"- ❌ {f['metric']}.{f['rule']}: {f['message']}")
            if smp.get("judge") and smp["judge"].get("unsupported_claims"):
                L.append(f"- Judge, unsupported: {smp['judge']['unsupported_claims']}")
            L.append("")
    return "\n".join(L) + "\n"
