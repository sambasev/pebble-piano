#!/usr/bin/env python3
"""Hackathon probe: how well does Muse Spark read Beyer Op. 101, and what does SAM 3.1
find on the page? Standard library only. Results go to .build/ai-probe/ (git-ignored).

    python3 scripts/ai_probe.py              # all three pieces + SAM on both pages
    python3 scripts/ai_probe.py --only 12    # one piece

The key comes from MODEL_API_KEY, or else from the Keychain item the app's AI settings
saved, so it never needs to be typed or pasted.
"""
import argparse, base64, json, os, re, subprocess, sys, time, urllib.request, urllib.error

BASE = "https://api.meta.ai/v1"
SPARK = "muse-spark-1.3"
SAM = "sam-3.1"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "Fixtures", "beyer")
OUT = os.path.join(ROOT, ".build", "ai-probe")

# (piece number, page image, what to tell the model about where it is)
PIECES = [
    ("12", "op101-p24.png", "the piece numbered 12 (the first piece on the page, marked Moderato)"),
    ("13", "op101-p24.png", "the piece numbered 13 (the second piece on the page)"),
    ("24", "op101-p27.png", "the piece numbered 24, titled 'Kinderlied — Child's Song' (two systems)"),
]
SAM_PROMPTS = ["music staff", "grand staff"]

SYSTEM = """You are an expert music engraver transcribing printed piano music into MusicXML.
Transcribe exactly what is printed; never correct, simplify or complete the music.
Rules:
- Output one MusicXML 3.1 score-partwise document with ONE part (P1, "Piano") and <staves>2</staves>.
  Staff 1 is the upper staff, staff 2 the lower staff. Use <backup> between staves in each measure.
- Read each staff's clef from the page. In this book the lower staff is often a TREBLE clef
  (the left hand plays above middle C); do not assume a bass clef.
- Include the time signature, key signature, every note and rest with its exact duration,
  ties, repeat barlines and printed fingering numbers as <notations><technical><fingering>.
- Use <divisions>4</divisions> (a quarter note is 4).
- Skip dynamics, lyrics, slurs and tempo words.
- Reply with the MusicXML only: no explanation, no code fences."""


def api_key():
    k = os.environ.get("MODEL_API_KEY", "").strip()
    if k:
        return k
    try:
        return subprocess.run(
            ["security", "find-generic-password", "-s", "com.sambasev.perfectpiano.ai", "-a", "meta", "-w"],
            check=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        sys.exit("No key: save it in Pebble Piano's AI settings, or set MODEL_API_KEY.")


def post(path, body, key, accept="application/json"):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "Accept": accept})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {path}: {e.read()[:500].decode(errors='replace')}")
    return data, time.time() - t


def data_url(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def read_piece(key, number, page, where):
    body = {
        "model": SPARK,
        "reasoning_effort": "high",
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": [
                {"type": "text", "text": f"Transcribe {where} from this page of Beyer's Op. 101."},
                {"type": "image_url", "image_url": {"url": data_url(os.path.join(FIX, page))}},
            ]},
        ],
    }
    data, secs = post("/chat/completions", body, key)
    j = json.loads(data)
    text = j["choices"][0]["message"]["content"]
    text = re.sub(r"^```(?:xml)?\s*|\s*```$", "", text.strip())
    path = os.path.join(OUT, f"no{number}.musicxml")
    with open(path, "w") as f:
        f.write(text)
    u = j.get("usage", {})
    print(f"No. {number}: {secs:.1f}s in={u.get('prompt_tokens')} out={u.get('completion_tokens')} -> {path}")


def segment(key, page, prompt):
    body = {"model": SAM, "stream": True, "input": [{"type": "message", "role": "user", "content": [
        {"type": "input_text", "text": prompt},
        {"type": "input_image", "image_url": data_url(os.path.join(FIX, page))}]}]}
    data, secs = post("/responses", body, key, accept="text/event-stream")
    lines = []
    for raw in data.decode().splitlines():
        if raw.startswith("data:"):
            p = raw[5:].strip()
            if p and p != "[DONE]":
                ev = json.loads(p)
                if ev.get("type") == "response.output_text.delta":
                    lines.append(ev["delta"])
    text = "\n".join(lines)
    boxes = [tuple(int(v) for v in m) for m in re.findall(r"<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);", text)]
    name = f"sam-{page.replace('.png', '')}-{prompt.replace(' ', '-')}"
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump({"page": page, "prompt": prompt, "seconds": secs, "boxes": boxes}, f)
    print(f"SAM '{prompt}' on {page}: {secs:.1f}s, {len(boxes)} boxes")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="one piece number")
    ap.add_argument("--no-sam", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    key = api_key()
    for number, page, where in PIECES:
        if not a.only or a.only == number:
            read_piece(key, number, page, where)
    if not a.no_sam and not a.only:
        for page in sorted({p for _, p, _ in PIECES}):
            for prompt in SAM_PROMPTS:
                segment(key, page, prompt)
    print("Done. Results in", OUT)


if __name__ == "__main__":
    main()
