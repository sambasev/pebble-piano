#!/usr/bin/env python3
"""Expands the OMR evaluation benchmark using LilyPond sources.

Compiles LilyPond (.ly) two-hand piano exercises into:
  1. High-resolution rendered system PNG images (for vision model input)
  2. Ground-truth MIDI files
  3. Structured ground-truth JSON (truth/pieces.json: measures, staves, pitches, durations)

Can run locally (if lilypond is on PATH) or via Modal (cloud container with zero local setup).

Usage:
    # Run locally or via Modal on 5 pieces from Fixtures/lilypond
    ~/.local/bin/uv run --with music21 --with pillow --with modal python3 scripts/expand_benchmark.py --count 5
    ~/.local/bin/uv run --with music21 --with pillow --with modal python3 scripts/expand_benchmark.py --all
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LILY_DIR = ROOT / "Fixtures" / "lilypond"
DEFAULT_OUT_DIR = ROOT / "Fixtures" / "benchmark_expanded"

DURATION_MAP = {
    4.0: "whole", 2.0: "half", 1.0: "quarter", 0.5: "eighth", 0.25: "sixteenth",
    3.0: "half.", 1.5: "quarter.", 0.75: "eighth.", 0.375: "sixteenth."
}

# Modal image definition for cloud LilyPond compilation
def get_modal_app():
    import modal
    image = (
        modal.Image.debian_slim()
        .apt_install("lilypond", "poppler-utils", "ghostscript")
        .pip_install("music21", "pillow")
    )
    app = modal.App("perfectpiano-lilypond-compiler", image=image)
    return app, image

try:
    import modal
    app, image = get_modal_app()

    @app.function(image=image, timeout=600)
    def compile_remote(files_dict: dict, entry_filename: str) -> dict:
        """Compiles a LilyPond project remotely inside a container with lilypond installed."""
        import subprocess, glob
        from PIL import Image

        with tempfile.TemporaryDirectory() as td:
            for rel_path, content in files_dict.items():
                p = os.path.join(td, rel_path)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "wb") as f:
                    f.write(content if isinstance(content, bytes) else content.encode("utf-8"))

            target = os.path.join(td, entry_filename)
            stem = os.path.splitext(os.path.basename(target))[0]
            out_prefix = os.path.join(td, stem)

            # Compile LilyPond to PDF + MIDI (MIDI is emitted automatically when \midi {} is present)
            cmd = ["lilypond", "--pdf", f"-o{out_prefix}", target]
            res = subprocess.run(cmd, cwd=os.path.dirname(target), capture_output=True, text=True)
            if res.returncode != 0:
                return {"error": res.stderr}

            pdf_path = out_prefix + ".pdf"
            mid_paths = glob.glob(out_prefix + "*.midi") + glob.glob(out_prefix + "*.mid")

            if not os.path.exists(pdf_path):
                return {"error": f"No PDF generated. Stderr: {res.stderr}"}

            # Render PDF to PNG at 220 dpi
            png_cmd = ["pdftoppm", "-png", "-r", "220", pdf_path, out_prefix + "-page"]
            subprocess.run(png_cmd, capture_output=True)
            png_files = sorted(glob.glob(out_prefix + "-page*.png"))

            midi_data = None
            if mid_paths:
                with open(mid_paths[0], "rb") as mf:
                    midi_data = mf.read()

            pages_data = []
            for pf in png_files:
                with open(pf, "rb") as pf_f:
                    pages_data.append(pf_f.read())

            return {
                "pages": pages_data,
                "midi": midi_data,
                "log": res.stdout + "\n" + res.stderr
            }
except Exception:
    app = None


def midi_to_measures(midi_bytes: bytes) -> list:
    """Parses MIDI into structured measures [{upper: [[pitch, dur]], lower: [[pitch, dur]]}]."""
    from music21 import converter, note, chord

    with tempfile.NamedTemporaryFile(suffix=".mid", delete=False) as f:
        f.write(midi_bytes)
        tmp_name = f.name

    try:
        score = converter.parse(tmp_name, format="midi")
        parts = list(score.parts) or [score]
        staves = []
        for part in parts[:2]:
            bars = []
            for m in part.getElementsByClass("Measure"):
                items = []
                for n in m.notesAndRests:
                    d = DURATION_MAP.get(float(n.quarterLength), f"{float(n.quarterLength):.2f}")
                    if isinstance(n, note.Rest):
                        items.append(["r", d])
                    elif isinstance(n, chord.Chord):
                        items.append([n.pitches[-1].nameWithOctave, d])
                    else:
                        items.append([n.pitch.nameWithOctave, d])
                bars.append(items)
            staves.append(bars)

        while len(staves) < 2:
            staves.append([])

        max_bars = max(len(staves[0]), len(staves[1]))
        pad = lambda s, i: s[i] if i < len(s) else []
        return [{"upper": pad(staves[0], i), "lower": pad(staves[1], i)} for i in range(max_bars)]
    finally:
        if os.path.exists(tmp_name):
            os.remove(tmp_name)


def collect_lily_files(base_dir: Path) -> dict:
    """Collects all files needed for include resolution into a relative path dict."""
    files = {}
    for p in base_dir.rglob("*"):
        if p.is_file() and not p.name.startswith("."):
            rel = str(p.relative_to(base_dir))
            try:
                files[rel] = p.read_bytes()
            except Exception:
                pass
    return files


def main():
    ap = argparse.ArgumentParser(description="Expand OMR benchmark from LilyPond scores")
    ap.add_argument("--source", default=str(DEFAULT_LILY_DIR), help="Root folder of lilypond repo")
    ap.add_argument("--output", default=str(DEFAULT_OUT_DIR), help="Output folder for expanded benchmark")
    ap.add_argument("--count", type=int, default=10, help="Number of exercises to compile")
    ap.add_argument("--all", action="store_true", help="Compile all available exercises")
    ap.add_argument("--local", action="store_true", help="Force local lilypond execution")
    a = ap.parse_args()

    src = Path(a.source)
    out_dir = Path(a.output)
    img_dir = out_dir / "images"
    midi_dir = out_dir / "midi"
    truth_dir = out_dir / "truth"
    for d in (img_dir, midi_dir, truth_dir):
        d.mkdir(parents=True, exist_ok=True)

    single_pages = src / "single-pages"
    if not single_pages.exists():
        sys.exit(f"Source directory {single_pages} does not exist.")

    ly_files = sorted(list(single_pages.glob("*.ly")))
    if not a.all:
        ly_files = ly_files[:a.count]

    print(f"Found {len(ly_files)} exercises to compile into {out_dir}")
    has_local_lily = shutil.which("lilypond") is not None and not a.local

    all_files = collect_lily_files(src)
    pieces_manifest = {}

    for i, ly_path in enumerate(ly_files):
        piece_id = ly_path.stem
        print(f"[{i+1}/{len(ly_files)}] Compiling {piece_id}...")
        rel_entry = str(ly_path.relative_to(src))

        compiled = None
        if not a.local and app is not None:
            # Use Modal remote function
            try:
                with app.run():
                    compiled = compile_remote.remote(all_files, rel_entry)
            except Exception as e:
                print(f"  Modal compilation error: {e}")

        if not compiled or "error" in compiled:
            if shutil.which("lilypond"):
                # Fallback to local
                with tempfile.TemporaryDirectory() as td:
                    out_p = os.path.join(td, piece_id)
                    cmd = ["lilypond", "--pdf", f"-o{out_p}", str(ly_path)]
                    sub = subprocess.run(cmd, cwd=str(ly_path.parent), capture_output=True)
                    # Read generated files
                    pdf = out_p + ".pdf"
                    mid = out_p + ".midi"
                    if not os.path.exists(mid):
                        mid = out_p + ".mid"
                    if os.path.exists(pdf):
                        import glob
                        subprocess.run(["pdftoppm", "-png", "-r", "220", pdf, out_p + "-page"])
                        pngs = sorted(glob.glob(out_p + "-page*.png"))
                        compiled = {
                            "pages": [open(p, "rb").read() for p in pngs],
                            "midi": open(mid, "rb").read() if os.path.exists(mid) else None
                        }

        if not compiled or "error" in compiled or not compiled.get("pages"):
            print(f"  Failed: {compiled.get('error', 'unknown error') if compiled else 'no compiler available'}")
            continue

        # Save pages and midi
        crops = []
        for p_idx, page_bytes in enumerate(compiled["pages"]):
            crop_name = f"{piece_id}-p{p_idx+1}"
            crop_path = img_dir / f"{crop_name}.png"
            crop_path.write_bytes(page_bytes)
            crops.append(crop_name)

        midi_path = midi_dir / f"{piece_id}.mid"
        if compiled.get("midi"):
            midi_path.write_bytes(compiled["midi"])
            measures = midi_to_measures(compiled["midi"])
        else:
            measures = []

        pieces_manifest[piece_id] = {
            "title": piece_id.replace("_", " "),
            "crops": crops,
            "measures": measures
        }
        print(f"  ✓ Extracted {len(crops)} images, {len(measures)} measures")

    truth_file = truth_dir / "pieces.json"
    with open(truth_file, "w") as f:
        json.dump(pieces_manifest, f, indent=2)

    print(f"\nExpanded benchmark written to {out_dir}")
    print(f"Ground truth manifest: {truth_file} ({len(pieces_manifest)} pieces)")


if __name__ == "__main__":
    main()
