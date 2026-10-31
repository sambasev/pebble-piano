"""LEGATO (end-to-end OMR on Llama 3.2 Vision's image encoder) on a Modal GPU.

LEGATO reads an image of printed music and writes ABC notation; this app also turns the ABC
into MusicXML and a simple note list with music21. See https://github.com/guang-yng/legato.

One-time setup (see the hackathon notes for details):
  1. On Hugging Face, accept the licences for meta-llama/Llama-3.2-11B-Vision and
     guangyangmusic/legato, then create a read token.
  2. modal secret create huggingface HF_TOKEN=<that token>
Score the three Beyer pieces against the hand-checked truth (the first run downloads ~20 GB
of weights into a Modal volume, so it is slow once):
     modal run scripts/legato_modal.py
     modal run scripts/legato_modal.py --pieces no12 --beams 4
Deploy the HTTP endpoint (for the app; callers need a Modal proxy-auth token):
     modal deploy scripts/legato_modal.py
"""
import json
import os
import sys
import time

import modal

MODEL_ID = "guangyangmusic/legato"
CACHE = "/cache"

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("git")
    .run_commands("git clone --depth 1 https://github.com/guang-yng/legato /legato")
    # Inference only, at the repo's pinned versions. Its requirements.txt also lists training and
    # evaluation tools that can't install here (deepspeed builds CUDA code; musicdiff is git+ssh).
    .pip_install("torch==2.6.0", "transformers==4.54.0", "accelerate==1.8.0", "pillow==11.1.0",
                 "numpy==1.26.4", "tqdm", "sentencepiece", "protobuf")
    .pip_install("music21", "fastapi[standard]")
    .env({"PYTHONPATH": "/legato", "HF_HOME": CACHE})
)
weights = modal.Volume.from_name("legato-hf-cache", create_if_missing=True)
app = modal.App("perfectpiano-legato", image=image)

DURATION_NAMES = {4.0: "whole", 2.0: "half", 1.0: "quarter", 0.5: "eighth", 0.25: "sixteenth",
                  3.0: "half.", 1.5: "quarter.", 0.75: "eighth."}


def abc_to_reading(abc: str) -> dict:
    """ABC → {musicxml, measures: [{upper: [[name, duration]], lower: [...]}]} via music21."""
    from music21 import converter, note, chord
    from music21.musicxml.m21ToXml import GeneralObjectExporter

    score = converter.parse(abc, format="abc")
    parts = list(score.parts) or [score]
    staves = []
    for part in parts[:2]:
        bars = []
        for m in part.getElementsByClass("Measure"):
            items = []
            for n in m.notesAndRests:
                d = DURATION_NAMES.get(float(n.quarterLength), str(float(n.quarterLength)))
                if isinstance(n, note.Rest):
                    items.append(["r", d])
                elif isinstance(n, chord.Chord):
                    items.append([[p.nameWithOctave for p in n.pitches], d])
                else:
                    items.append([n.pitch.nameWithOctave, d])
            bars.append(items)
        staves.append(bars)
    while len(staves) < 2:
        staves.append([])
    count = max(len(staves[0]), len(staves[1]))
    pad = lambda s, i: s[i] if i < len(s) else []
    measures = [{"upper": pad(staves[0], i), "lower": pad(staves[1], i)} for i in range(count)]
    try:
        xml = GeneralObjectExporter(score).parse().decode()
    except Exception as e:  # keep the reading even if export fails
        xml = f"<!-- MusicXML export failed: {e} -->"
    return {"musicxml": xml, "measures": measures}


@app.cls(gpu="L40S", volumes={CACHE: weights}, secrets=[modal.Secret.from_name("huggingface")],
         timeout=900, scaledown_window=300)
class Legato:
    fp16: bool = modal.parameter(default=False)

    @modal.enter()
    def load(self):
        import torch
        from transformers import AutoProcessor
        from legato.models import LegatoModel

        t = time.time()
        self.processor = AutoProcessor.from_pretrained(MODEL_ID)
        self.model = LegatoModel.from_pretrained(MODEL_ID).to("cuda").eval()
        if self.fp16:
            self.model = self.model.half()
        weights.commit()  # keep downloaded weights for the next container
        print(f"loaded in {time.time() - t:.0f}s")

    @modal.method()
    def read(self, png: bytes, beams: int = 10) -> dict:
        import io
        import torch
        from PIL import Image
        from transformers import GenerationConfig

        img = Image.open(io.BytesIO(png)).convert("RGB")
        inputs = self.processor(images=[img], truncation=True, return_tensors="pt")
        dtype = torch.float16 if self.fp16 else None
        inputs = {k: (v.to("cuda", dtype=dtype) if (dtype and v.is_floating_point()) else v.to("cuda"))
                  for k, v in inputs.items()}
        config = GenerationConfig(max_length=2048, num_beams=beams, repetition_penalty=1.1)
        t = time.time()
        with torch.no_grad():
            out = self.model.generate(**inputs, generation_config=config, use_model_defaults=False)
        abc = self.processor.batch_decode(out, skip_special_tokens=True)[0]
        result = {"abc": abc, "seconds": time.time() - t}
        try:
            result.update(abc_to_reading(abc))
        except Exception as e:
            result["error"] = f"ABC parse failed: {e}"
        return result

    @modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
    def http(self, body: dict) -> dict:
        """POST {"image": <base64 PNG>, "beams": 10}. Needs Modal-Key / Modal-Secret headers."""
        import base64
        return self.read.local(base64.b64decode(body["image"]), int(body.get("beams", 10)))


@app.local_entrypoint()
def main(pieces: str = "no12,no13,no24", beams: int = 10, fp16: bool = False, full_page: bool = False):
    """Reads the Beyer crops and scores them like scripts/ai_probe2.py.
    --full-page instead sends whole pages 24 and 27 (closer to LEGATO's training data) and prints the ABC."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if full_page:
        legato = Legato(fp16=fp16)
        out_dir = os.path.join(root, ".build", "legato")
        os.makedirs(out_dir, exist_ok=True)
        for page in ("op101-p24", "op101-p27"):
            with open(os.path.join(root, "Fixtures", "beyer", page + ".png"), "rb") as f:
                r = legato.read.remote(f.read(), beams)
            json.dump(r, open(os.path.join(out_dir, f"{page}.json"), "w"), indent=1)
            print(f"== {page} ({r['seconds']:.0f}s)\n{r['abc'][:1200]}\n")
        return
    sys.path.insert(0, os.path.join(root, "scripts"))
    from ai_probe2 import score

    truth = json.load(open(os.path.join(root, "Fixtures", "beyer", "truth", "pieces.json")))
    out_dir = os.path.join(root, ".build", "legato")
    os.makedirs(out_dir, exist_ok=True)
    legato = Legato(fp16=fp16)
    for piece in pieces.split(","):
        t = truth[piece]
        measures, secs = [], 0.0
        for crop in t["crops"]:
            with open(os.path.join(root, "Fixtures", "beyer", "crops", crop + ".png"), "rb") as f:
                r = legato.read.remote(f.read(), beams)
            secs += r["seconds"]
            json.dump(r, open(os.path.join(out_dir, f"{crop}.json"), "w"), indent=1)
            if "error" in r:
                print(f"{crop}: {r['error']}\nABC:\n{r['abc']}")
            measures += r.get("measures", [])
        right, total, bars = score(measures, t["measures"])
        print(f"legato {piece}: notes {right}/{total} ({100 * right / total:.0f}%), bars exact "
              f"{bars}/{len(t['measures'])}, measures read {len(measures)}, {secs:.0f}s on GPU")
    print("Readings (ABC, MusicXML, notes) in", out_dir)
