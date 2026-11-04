"""The tutor model, called the way the app calls it, with latency measured on the stream.

Mirrors ModelTutorChatClient.messages / ModelClient.chatStreaming: system prompt, history
(app turns prefixed "App observation (data): "), then the context and question as one user
message, JSON-schema output, reasoning_effort low, max_tokens 2048, streamed with usage.

Latency, per call:
  ttft_s    first content delta from the server
  ttfv_s    first visible text: the moment the app would show reply text (after
            `"on_topic": true` and the start of "reply"), what the learner actually waits for
  total_s   the whole reply
"""
from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional

BASE_URL = os.environ.get("MODEL_BASE_URL", "https://api.meta.ai/v1")


def api_key() -> Optional[str]:
    key = os.environ.get("MODEL_API_KEY", "").strip()
    if key:
        return key
    try:  # the app's Keychain item, on a Mac
        return subprocess.run(["security", "find-generic-password", "-s", "com.sambasev.perfectpiano.ai", "-a", "meta", "-w"],
                              capture_output=True, text=True, check=True).stdout.strip() or None
    except Exception:
        return None


def messages(system: str, history: List[Dict[str, str]], prompt: str, question: str,
             image_path: Optional[str] = None) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = [{"role": "system", "content": system}]
    for turn in history:
        if turn["role"] == "app":
            out.append({"role": "user", "content": "App observation (data): " + turn["text"]})
        else:
            out.append({"role": turn["role"], "content": turn["text"]})
    text = f"<context>\n{prompt}\n</context>\n\nLearner's question: {question}"
    if image_path:
        b64 = base64.b64encode(open(image_path, "rb").read()).decode()
        mime = "image/png" if image_path.endswith(".png") else "image/jpeg"
        out.append({"role": "user", "content": [{"type": "text", "text": text},
                                                {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}}]})
    else:
        out.append({"role": "user", "content": text})
    return out


VISIBLE = re.compile(r'"on_topic"\s*:\s*true.*"reply"\s*:\s*"(?:[^"\\]|\\.)+', re.S)


def chat(key: str, model: str, msgs: List[Dict[str, Any]], schema: Dict[str, Any], *,
         reasoning: str = "low", max_tokens: int = 2048, timeout: float = 45, retries: int = 2) -> Dict[str, Any]:
    """One streamed call. Returns {output, raw, latency{...}, usage{...}, error}."""
    body = {"model": model, "messages": msgs, "response_format": {"type": "json_schema", "json_schema": schema},
            "reasoning_effort": reasoning, "max_tokens": max_tokens, "stream": True,
            "stream_options": {"include_usage": True}}
    last_error = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(f"{BASE_URL}/chat/completions", data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                              "Accept": "text/event-stream"})
        t0 = time.monotonic()
        ttft = ttfv = None
        text, usage = "", {}
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                for raw in resp:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    event = json.loads(data)
                    if event.get("error"):
                        raise RuntimeError(event["error"].get("message", "stream error"))
                    for choice in event.get("choices") or []:
                        piece = (choice.get("delta") or {}).get("content")
                        if piece:
                            if ttft is None:
                                ttft = time.monotonic() - t0
                            text += piece
                            if ttfv is None and VISIBLE.search(text):
                                ttfv = time.monotonic() - t0
                    if event.get("usage"):
                        usage = event["usage"]
            total = time.monotonic() - t0
            try:
                output = json.loads(text)
            except json.JSONDecodeError:
                output = None  # the app treats an unreadable reply as a refusal
            out_tokens = usage.get("completion_tokens")
            return {"output": output, "raw": text, "error": None if output is not None else "unparseable JSON",
                    "latency": {"ttft_s": ttft, "ttfv_s": ttfv, "total_s": total,
                                "tokens_per_s": (out_tokens / (total - (ttft or 0))) if out_tokens and total > (ttft or 0) else None},
                    "usage": {"input": usage.get("prompt_tokens"), "output": out_tokens}, "attempts": attempt + 1}
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, RuntimeError, ConnectionError) as exc:
            detail = exc.read().decode("utf-8", "replace")[:300] if isinstance(exc, urllib.error.HTTPError) else str(exc)
            last_error = f"{type(exc).__name__}: {detail}"
            retryable = not isinstance(exc, urllib.error.HTTPError) or exc.code in (408, 409, 429) or exc.code >= 500
            if not retryable or attempt == retries:
                break
            time.sleep(2 ** (attempt + 1))
    return {"output": None, "raw": "", "error": last_error, "latency": {"ttft_s": None, "ttfv_s": None, "total_s": None},
            "usage": {}, "attempts": retries + 1}
