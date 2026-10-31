#!/usr/bin/env python3
"""Hackathon probe 2: read one cropped system at a time, as staff positions rather than
pitches, and score the result against hand-checked notes (Fixtures/beyer/truth).

    python3 scripts/ai_probe2.py                         # Muse Spark 1.3 and Muse Wonder, all pieces, plus SAM
    python3 scripts/ai_probe2.py --models muse-spark-1.3 --pieces no12

The model reports where each notehead sits on its staff; this script turns that into a pitch
from the clef, so octave mistakes can't happen. Results go to .build/ai-probe2/.
Key: MODEL_API_KEY, or the Keychain item PerfectPiano's AI settings saved.
"""
import argparse, base64, json, os, re, subprocess, sys, time, urllib.request, urllib.error

BASE = "https://api.meta.ai/v1"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "Fixtures", "beyer")
OUT = os.path.join(ROOT, ".build", "ai-probe2")

PROMPT = """This image is one or more systems of beginner piano music: an upper and a lower staff joined by a brace.
For every measure, left to right, list each staff's notes and rests in order.

Give each note's vertical POSITION on its own staff as an integer, counted in steps (lines and spaces):
  0 = bottom line, 1 = space above the bottom line, 2 = second line, 3 = second space, 4 = middle line,
  5 = third space, 6 = fourth line, 7 = top space, 8 = top line, 9 = space just above the top line,
  10 = first ledger line above, -1 = space just below the bottom line, -2 = first ledger line below.
Read each staff's clef from the image; in this book BOTH staves are often treble.
Durations: whole (hollow, no stem), half (hollow, stem), quarter (filled, stem), eighth (filled, flag or beam).
finger = a printed fingering number (1-5) above or below that note, else null. Ignore text, slurs and dynamics.
Count the barlines first so the number of measures is right."""

STAFF = {
    "type": "object", "additionalProperties": False, "required": ["clef", "notes"],
    "properties": {
        "clef": {"type": "string", "enum": ["treble", "bass"]},
        "notes": {"type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["rest", "position", "duration", "dotted", "accidental", "finger"],
            "properties": {
                "rest": {"type": "boolean"},
                "position": {"type": "integer"},
                "duration": {"type": "string", "enum": ["whole", "half", "quarter", "eighth", "sixteenth"]},
                "dotted": {"type": "boolean"},
                "accidental": {"type": "string", "enum": ["none", "sharp", "flat", "natural"]},
                "finger": {"type": ["integer", "null"]},
            }}},
    }}
SCHEMA = {
    "type": "object", "additionalProperties": False, "required": ["measureCount", "measures"],
    "properties": {
        "measureCount": {"type": "integer"},
        "measures": {"type": "array", "items": {
            "type": "object", "additionalProperties": False, "required": ["upper", "lower"],
            "properties": {"upper": STAFF, "lower": STAFF}}},
    }}

LETTERS = "CDEFGAB"
BOTTOM_LINE = {"treble": 4 * 7 + 2, "bass": 2 * 7 + 4}  # E4, G2 as diatonic indices


def pitch(clef, position):
    i = BOTTOM_LINE[clef] + position
    return f"{LETTERS[i % 7]}{i // 7}"


def api_key():
    k = os.environ.get("MODEL_API_KEY", "").strip()
    if k:
        return k
    try:
        return subprocess.run(["security", "find-generic-password", "-s", "com.sambasev.perfectpiano.ai",
                               "-a", "meta", "-w"], check=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        sys.exit("No key: save it in PerfectPiano's AI settings, or set MODEL_API_KEY.")


def post(path, body, key, accept="application/json"):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json", "Accept": accept})
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            return r.read(), time.time() - t
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read()[:400].decode(errors='replace')}")


CROPS_DIR = "crops"


def image(name):
    with open(os.path.join(FIX, CROPS_DIR, name + ".png"), "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def read_crop(key, model, crop, effort):
    # Streamed: long reasoning runs past the server's time limit for non-streaming requests.
    body = {"model": model, "reasoning_effort": effort, "stream": True, "stream_options": {"include_usage": True},
            "response_format": {"type": "json_schema", "json_schema": {"name": "Systems", "schema": SCHEMA}},
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": PROMPT}, {"type": "image_url", "image_url": {"url": image(crop)}}]}]}
    data, secs = post("/chat/completions", body, key, accept="text/event-stream")
    parts, usage = [], {}
    for line in data.decode().splitlines():
        if not line.startswith("data:") or line[5:].strip() in ("", "[DONE]"):
            continue
        ev = json.loads(line[5:])
        if ev.get("error"):
            raise RuntimeError(ev["error"].get("message", ev["error"]))
        for c in ev.get("choices") or []:
            parts.append((c.get("delta") or {}).get("content") or "")
        usage = ev.get("usage") or usage
    text = "".join(parts)
    try:
        return json.loads(text), secs, usage
    except json.JSONDecodeError:
        raise RuntimeError(f"reply isn't JSON: {text[:200]!r}")


def to_notes(staff):
    out = []
    for n in staff["notes"]:
        p = "r" if n["rest"] else pitch(staff["clef"], n["position"])
        out.append([p, n["duration"] + ("." if n["dotted"] else "")])
    return out


def score(read, truth):
    """Notes right in the right measure, per staff, by position in the measure."""
    right = total = bars_right = 0
    for i, t in enumerate(truth):
        r = read[i] if i < len(read) else {"upper": [], "lower": []}
        bar_ok = True
        for s in ("upper", "lower"):
            total += len(t[s])
            for j, note in enumerate(t[s]):
                if j < len(r[s]) and r[s][j] == note:
                    right += 1
            bar_ok &= r[s] == t[s]
        bars_right += bar_ok
    return right, total, bars_right


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="muse-spark-1.3,muse-wonder-1.0")
    ap.add_argument("--pieces", default="no12,no13,no24")
    ap.add_argument("--no-sam", action="store_true")
    ap.add_argument("--effort", default="medium", help="reasoning effort: minimal, low, medium, high")
    ap.add_argument("--images", default="crops", help="folder under Fixtures/beyer: crops (1895 scan) or modern")
    a = ap.parse_args()
    global CROPS_DIR, OUT
    CROPS_DIR = a.images
    if a.images != "crops":
        OUT = os.path.join(OUT, a.images)
    os.makedirs(OUT, exist_ok=True)
    key = api_key()
    truth = json.load(open(os.path.join(FIX, "truth", "pieces.json")))
    report = []
    for model in a.models.split(","):
        for piece in a.pieces.split(","):
            t = truth[piece]
            measures, secs, ok, toks = [], 0.0, True, 0
            for crop in t["crops"]:
                try:
                    r, s, u = read_crop(key, model, crop, a.effort)
                except Exception as e:
                    print(f"{model} {crop}: ERROR {e}"); ok = False; break
                secs += s
                toks += u.get("completion_tokens") or 0
                json.dump(r, open(os.path.join(OUT, f"{model}-{crop}.json"), "w"), indent=1)
                measures += [{"upper": to_notes(m["upper"]), "lower": to_notes(m["lower"]),
                              "clefs": [m["upper"]["clef"], m["lower"]["clef"]]} for m in r["measures"]]
            if not ok:
                continue
            right, total, bars = score(measures, t["measures"])
            line = (f"{model:18} {piece}: notes {right}/{total} ({100 * right / total:.0f}%), "
                    f"bars exact {bars}/{len(t['measures'])}, measures read {len(measures)}, {secs:.0f}s, out={toks}")
            print(line); report.append(line)
            with open(os.path.join(OUT, f"{model}-{piece}.txt"), "w") as f:
                for i, m in enumerate(measures):
                    tm = t["measures"][i] if i < len(t["measures"]) else None
                    mark = "✓" if tm and m["upper"] == tm["upper"] and m["lower"] == tm["lower"] else "✗"
                    f.write(f"{mark} bar {i + 1} clefs {m['clefs']}\n   read  U {m['upper']}\n         L {m['lower']}\n")
                    if tm and mark == "✗":
                        f.write(f"   truth U {tm['upper']}\n         L {tm['lower']}\n")
    if not a.no_sam:
        for page in ("op101-p24.png", "op101-p27.png"):
            for prompt in ("music staff", "grand staff"):
                try:
                    with open(os.path.join(FIX, page), "rb") as f:
                        url = "data:image/png;base64," + base64.b64encode(f.read()).decode()
                    body = {"model": "sam-3.1", "stream": True, "input": [{"type": "message", "role": "user",
                            "content": [{"type": "input_text", "text": prompt}, {"type": "input_image", "image_url": url}]}]}
                    data, secs = post("/responses", body, key, accept="text/event-stream")
                    text = "\n".join(json.loads(l[5:])["delta"] for l in data.decode().splitlines()
                                     if l.startswith("data:") and '"response.output_text.delta"' in l)
                    boxes = [list(map(int, m)) for m in re.findall(r"<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);", text)]
                    json.dump({"page": page, "prompt": prompt, "boxes": boxes},
                              open(os.path.join(OUT, f"sam-{page[:-4]}-{prompt.replace(' ', '-')}.json"), "w"))
                    line = f"SAM '{prompt}' on {page}: {len(boxes)} boxes, {secs:.0f}s"
                except Exception as e:
                    line = f"SAM '{prompt}' on {page}: ERROR {e}"
                print(line); report.append(line)
    open(os.path.join(OUT, "report.txt"), "w").write("\n".join(report) + "\n")
    print("Done. Results in", OUT)


if __name__ == "__main__":
    main()
