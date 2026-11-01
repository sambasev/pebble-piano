"""ByteDance High-Resolution Piano Transcription on a Modal GPU.

Hosts ByteDance's piano transcription neural network (Qiuqiang Kong et al., IEEE/ACM TASLP 2021)
on a serverless GPU for real-time / retrospective bar-by-bar transcription and grading.

Transcribes:
- Exact continuous note onsets & offsets
- Note velocities (dynamics: pp ... ff)
- Sustain pedal down/up events

One-time setup:
  1. modal secret create huggingface HF_TOKEN=<token> (if needed) or run directly.
  2. Test locally on GPU:
       modal run scripts/bytedance_modal.py --audio Fixtures/transcription/take1.wav
  3. Deploy the HTTP endpoint:
       modal deploy scripts/bytedance_modal.py
"""

import base64
import io
import json
import os
import sys
import time
from pathlib import Path

import modal

MODEL_NAME = "CRNN_note_F1=0.9677_pedal_F1=0.9186.pth"
ZENODO_URL = f"https://zenodo.org/record/4034264/files/{MODEL_NAME}?download=1"
CACHE_DIR = "/cache/bytedance_weights"

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("git", "wget", "ffmpeg", "libsndfile1")
    .pip_install(
        "torch==2.5.1",
        "torchaudio==2.5.1",
        "numpy<2.0.0",
        "librosa==0.10.2",
        "soundfile==0.12.1",
        "resampy==0.4.3",
        "mido==1.3.3",
        "piano_transcription_inference==0.0.6",
        "fastapi[standard]"
    )
    .env({"TORCH_HOME": CACHE_DIR})
)

weights_volume = modal.Volume.from_name("bytedance-weights-cache", create_if_missing=True)
app = modal.App("perfectpiano-bytedance", image=image)


@app.cls(
    gpu="T4",
    volumes={CACHE_DIR: weights_volume},
    timeout=600,
    scaledown_window=300
)
class ByteDancePianoTranscriber:
    @modal.enter()
    def load(self):
        import torch
        from piano_transcription_inference import PianoTranscription

        checkpoint_path = os.path.join(CACHE_DIR, MODEL_NAME)
        if not os.path.exists(checkpoint_path) or os.path.getsize(checkpoint_path) < 1.6e8:
            print(f"Downloading official ByteDance checkpoint from {ZENODO_URL}...")
            os.makedirs(CACHE_DIR, exist_ok=True)
            t_dl = time.time()
            os.system(f'wget -O "{checkpoint_path}" "{ZENODO_URL}"')
            weights_volume.commit()
            print(f"Downloaded ByteDance checkpoint ({os.path.getsize(checkpoint_path)/1e6:.1f} MB) in {time.time()-t_dl:.1f}s")

        print("Initializing ByteDance Note_pedal CRNN on CUDA...")
        t0 = time.time()
        self.transcriptor = PianoTranscription(
            model_type="Note_pedal",
            checkpoint_path=checkpoint_path,
            device="cuda" if torch.cuda.is_available() else "cpu"
        )
        print(f"ByteDance model ready in {time.time() - t0:.2f}s")

    @modal.method()
    def transcribe_audio_samples(
        self,
        audio_samples: bytes,
        sample_rate: int = 16000,
        measure_index: int = 0,
        start_time_offset: float = 0.0,
        lead_in_padding: float = 0.0
    ) -> dict:
        return self._transcribe(
            audio_samples=audio_samples,
            sample_rate=sample_rate,
            measure_index=measure_index,
            start_time_offset=start_time_offset,
            lead_in_padding=lead_in_padding
        )

    def _transcribe(
        self,
        audio_samples: bytes,
        sample_rate: int = 16000,
        measure_index: int = 0,
        start_time_offset: float = 0.0,
        lead_in_padding: float = 0.0
    ) -> dict:
        """Transcribe an audio chunk (WAV bytes or raw float32).

        Args:
            audio_samples: WAV file bytes or raw float32 mono bytes.
            sample_rate: Audio sampling rate.
            measure_index: 0-based or 1-based measure index.
            start_time_offset: Physical start time in seconds relative to the take.
            lead_in_padding: Lead-in padding in seconds to subtract from detected onsets.
        """
        import soundfile as sf
        import numpy as np
        import resampy

        # Try reading as WAV file, or assume raw float32 mono
        try:
            with io.BytesIO(audio_samples) as bio:
                audio, sr = sf.read(bio)
                if audio.ndim > 1:
                    audio = np.mean(audio, axis=1)
        except Exception:
            audio = np.frombuffer(audio_samples, dtype=np.float32)
            sr = sample_rate

        # ByteDance expects 16,000 Hz
        if sr != 16000:
            audio = resampy.resample(audio, sr, 16000)
            sr = 16000

        t0 = time.time()
        result = self.transcriptor.transcribe(audio, midi_path=None)
        inference_time_ms = (time.time() - t0) * 1000.0

        est_notes = result.get("est_note_events", [])
        est_pedals = result.get("est_pedal_events", [])

        # Shift timestamps relative to take start
        # onset_in_take = start_time_offset + (onset - lead_in_padding)
        notes_out = []
        for n in est_notes:
            onset = float(n["onset_time"]) - lead_in_padding
            offset = float(n["offset_time"]) - lead_in_padding
            notes_out.append({
                "pitch": int(n["midi_note"]),
                "onset": max(0.0, onset + start_time_offset),
                "offset": max(0.0, offset + start_time_offset),
                "duration": max(0.01, offset - onset),
                "velocity": int(n["velocity"])
            })

        pedals_out = []
        for p in est_pedals:
            onset = float(p["onset_time"]) - lead_in_padding
            offset = float(p["offset_time"]) - lead_in_padding
            pedals_out.append({
                "onset": max(0.0, onset + start_time_offset),
                "offset": max(0.0, offset + start_time_offset)
            })

        return {
            "measure_index": measure_index,
            "inference_time_ms": inference_time_ms,
            "audio_duration_sec": len(audio) / 16000.0,
            "notes": notes_out,
            "pedals": pedals_out
        }

    @modal.fastapi_endpoint(method="POST")
    def transcribe_bar(self, body: dict) -> dict:
        """HTTP endpoint for bar-by-bar retrospective transcription.

        Body schema:
        {
            "audio_base64": "<base64 encoded WAV or raw float32 mono>",
            "sample_rate": 16000,
            "measure_index": 1,
            "start_time_offset": 2.0,
            "lead_in_padding": 0.15
        }
        """
        raw_bytes = base64.b64decode(body["audio_base64"])
        sample_rate = int(body.get("sample_rate", 16000))
        measure_index = int(body.get("measure_index", 0))
        start_time_offset = float(body.get("start_time_offset", 0.0))
        lead_in_padding = float(body.get("lead_in_padding", 0.0))

        return self._transcribe(
            audio_samples=raw_bytes,
            sample_rate=sample_rate,
            measure_index=measure_index,
            start_time_offset=start_time_offset,
            lead_in_padding=lead_in_padding
        )


@app.local_entrypoint()
def main(audio: str = "Fixtures/transcription/take1.wav", bar_duration: float = 2.0):
    """Test ByteDance bar-by-bar transcription on a local audio file."""
    import soundfile as sf
    import numpy as np

    print(f"Loading test audio: {audio}...")
    data, sr = sf.read(audio)
    if data.ndim > 1:
        data = np.mean(data, axis=1)

    transcriber = ByteDancePianoTranscriber()
    total_duration = len(data) / float(sr)
    print(f"Audio duration: {total_duration:.2f}s. Slicing into {bar_duration}s bars...")

    current_t = 0.0
    bar_idx = 1

    while current_t < total_duration:
        end_t = min(total_duration, current_t + bar_duration)
        s_start = int(current_t * sr)
        s_end = int(end_t * sr)
        bar_chunk = data[s_start:s_end].astype(np.float32).tobytes()

        res = transcriber.transcribe_audio_samples.remote(
            audio_samples=bar_chunk,
            sample_rate=sr,
            measure_index=bar_idx,
            start_time_offset=current_t,
            lead_in_padding=0.0
        )

        notes = res["notes"]
        pedals = res["pedals"]
        inf_ms = res["inference_time_ms"]
        print(f"Measure {bar_idx:2d} (t={current_t:4.1f}s-{end_t:4.1f}s) -> GPU inf: {inf_ms:5.1f}ms | Notes: {len(notes)} | Pedals: {len(pedals)}")
        for n in notes:
            print(f"   pitch={n['pitch']:2d} vel={n['velocity']:3d} onset={n['onset']:5.2f}s offset={n['offset']:5.2f}s")

        current_t = end_t
        bar_idx += 1
