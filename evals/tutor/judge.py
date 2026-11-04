"""LLM judge: what rules can't see (teaching quality, claim-level grounding, useful follow-ups).

Backends, picked with --judge (default: auto):
  claude   Claude Opus 5.5 through the official `anthropic` SDK (pip install anthropic), with
           structured output. A judge from a different model family than the tutor avoids the
           self-preference bias of a model grading its own outputs; prefer it.
  meta     the Meta API (same key as the tutor), with a stronger model/effort. Same-family:
           treat its scores as a weaker signal.
  none     deterministic scorers only.

The judge gets the full context the tutor saw, the reply, the case's rubric, and returns
1–5 scores plus every claim it found unsupported, quoted. `--calibrate` runs it on
hand-labelled replies (calibration.py) and reports agreement, so you know whether to trust it.
"""
from __future__ import annotations

import json
import os
import urllib.request
from typing import Any, Dict, Optional

CLAUDE_MODEL = "claude-opus-5-5"
META_JUDGE_MODEL = os.environ.get("JUDGE_META_MODEL", "muse-spark-1.3")

SCHEMA = {
    "type": "object",
    "properties": {
        "unsupported_claims": {"type": "array", "items": {"type": "string"},
                               "description": "Each claim in the reply that the context doesn't support, quoted."},
        "grounding": {"type": "integer", "description": "1-5: 5 = every specific claim is supported by the context"},
        "helpfulness": {"type": "integer", "description": "1-5: answers the question and does what the rubric asks"},
        "teaching": {"type": "integer", "description": "1-5: warm, concrete, one practical tip, like a teacher beside the learner"},
        "followups": {"type": "integer", "description": "1-5: suggestions are relevant, distinct, natural next steps the app can do; 3 if none were needed"},
        "rationale": {"type": "string"},
    },
    "required": ["unsupported_claims", "grounding", "helpfulness", "teaching", "followups", "rationale"],
    "additionalProperties": False,
}

INSTRUCTIONS = """You grade one reply from an AI piano tutor inside a practice app. You are strict and specific.

You get: the context the tutor saw (score data, grader evidence, progress, app guide; it is the ONLY source of
truth about this learner and piece), the learner's question, the tutor's reply (text, actions the app will run,
follow-up suggestion chips) and a rubric written by the eval's author.

Grounding: list every specific claim about the piece, the learner's playing, their history or the app that the
context does not support (wrong notes or bars, invented markings, dynamics, fingering, dates, scores, memories,
buttons). General music knowledge (what a half note is, how to relax a wrist) is fine. Score 5 only if the list is empty.
Helpfulness: does it answer what was asked and do what the rubric says a good answer does?
Teaching: warm and encouraging, concrete, one practical next step; no report-like numbers unless asked.
Follow-ups: relevant to this moment, distinct, in the learner's voice, possible in the app (e.g. no left-hand
practice on a one-track piece). Score 3 when the reply is a refusal or chips weren't expected.
Return only the JSON object."""


def _prompt(case: Dict[str, Any], context_prompt: str, output: Dict[str, Any]) -> str:
    actions = [{k: v for k, v in a.items() if v is not None} for a in output.get("actions") or []]
    return (f"<context>\n{context_prompt}\n</context>\n\n<question>{case['question']}</question>\n\n"
            f"<audience>{case.get('audience', 'adult')}</audience>\n\n"
            f"<reply>{output.get('reply', '')}</reply>\n<on_topic>{output.get('on_topic')}</on_topic>\n"
            f"<actions>{json.dumps(actions)}</actions>\n<suggestions>{json.dumps(output.get('suggestions') or [])}</suggestions>\n\n"
            f"<rubric>{case.get('judge') or 'No extra rubric: judge against the context and the question.'}</rubric>")


class Judge:
    def __init__(self, backend: str, meta_key: Optional[str] = None):
        self.backend = backend
        self.meta_key = meta_key
        if backend == "claude":
            import anthropic  # pip install anthropic
            # Explicit base URL: a sandbox may set ANTHROPIC_BASE_URL for its own use.
            self.client = anthropic.Anthropic(base_url=os.environ.get("JUDGE_ANTHROPIC_BASE_URL", "https://api.anthropic.com"))

    @staticmethod
    def pick(choice: str, meta_key: Optional[str]) -> "Judge":
        if choice == "auto":
            try:
                import anthropic  # noqa: F401
                choice = "claude" if os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN") else ""
            except ImportError:
                choice = ""
            choice = choice or ("meta" if meta_key else "none")
        return Judge(choice, meta_key)

    def grade(self, case: Dict[str, Any], context_prompt: str, output: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if self.backend == "none" or not isinstance(output, dict):
            return None
        user = _prompt(case, context_prompt, output)
        try:
            if self.backend == "claude":
                resp = self.client.messages.create(
                    model=CLAUDE_MODEL, max_tokens=16000, system=INSTRUCTIONS,
                    output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
                    messages=[{"role": "user", "content": user}])
                if resp.stop_reason == "refusal":
                    return {"error": "judge refused"}
                text = next(b.text for b in resp.content if b.type == "text")
            else:
                body = {"model": META_JUDGE_MODEL, "reasoning_effort": "high", "max_tokens": 4096,
                        "messages": [{"role": "system", "content": INSTRUCTIONS}, {"role": "user", "content": user}],
                        "response_format": {"type": "json_schema", "json_schema": {"name": "grade", "schema": SCHEMA}}}
                req = urllib.request.Request(f"{os.environ.get('MODEL_BASE_URL', 'https://api.meta.ai/v1')}/chat/completions",
                                             data=json.dumps(body).encode(), method="POST",
                                             headers={"Authorization": f"Bearer {self.meta_key}", "Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=90) as r:
                    text = json.loads(r.read())["choices"][0]["message"]["content"]
            grade = json.loads(text)
            grade["judge"] = f"{self.backend}:{CLAUDE_MODEL if self.backend == 'claude' else META_JUDGE_MODEL}"
            return grade
        except Exception as exc:  # a judge failure never fails the case; it's reported
            return {"error": f"{type(exc).__name__}: {exc}"[:300]}
