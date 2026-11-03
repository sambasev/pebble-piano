#!/usr/bin/env python3
"""Opt-in network verification of the pinned Mutopia catalog (stdlib + curl)."""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import pathlib
import struct
import subprocess

def midi_notes(data):
 if data[:4]!=b'MThd':raise ValueError('not MIDI')
 _,n,ppq=struct.unpack('>HHH',data[8:14]);pos=8+int.from_bytes(data[4:8],'big');notes=[];times=[];keys=[]
 for tr in range(n):
  size=int.from_bytes(data[pos+4:pos+8],'big');b=data[pos+8:pos+8+size];pos+=8+size;i=0;t=0;running=None;active={}
  def vlq():
   nonlocal i
   v=0
   while True:
    a=b[i];i+=1;v=v*128+(a&127)
    if a<128:return v
  while i<len(b):
   t+=vlq();s=b[i]
   if s&128:i+=1;running=s
   else:s=running
   if s==255:
    typ=b[i];i+=1;ln=vlq();payload=b[i:i+ln];i+=ln;running=None
    if typ==88:times.append((t,tuple(payload[:2])))
    if typ==89 and len(payload)==2:keys.append((t,dict(fifths=struct.unpack('b',payload[:1])[0],isMinor=bool(payload[1]))))
    if typ==47:break
   elif s in (240,247):ln=vlq();i+=ln;running=None
   else:
    kind=s>>4;ch=s&15;p=b[i];i+=1;v=0
    if kind not in (12,13):v=b[i];i+=1
    if kind==9 and v:active[(ch,p)]=t
    elif kind==8 or(kind==9 and not v):
     start=active.pop((ch,p),None)
     if start is not None:notes.append(dict(track=tr,channel=ch,pitch=p,on=start/ppq,off=t/ppq))
 return notes,times,keys


def validate(piece, directory):
    path = directory / (piece["id"] + ".mid")
    subprocess.run(["curl", "--silent", "--show-error", "--fail", "--location", "--max-time", "45", piece["midiURL"], "--output", str(path)], check=True)
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == piece["sha256"], "checksum differs"
    notes, metres, keys = midi_notes(data)
    opening_key = min(keys, key=lambda item: item[0])[1] if keys else None
    assert piece.get("keySignature") == opening_key, "opening key signature differs"
    assert notes and all(n["channel"] != 9 and 21 <= n["pitch"] <= 108 for n in notes), "not solo piano MIDI"
    assert len(set(value for tick, value in metres)) <= 1, "metre changes"
    assert all(abs(n[key] * 4 - round(n[key] * 4)) < 0.015 for n in notes for key in ["on", "off"]), "off the sixteenth grid"
    tracks = set(n["track"] for n in notes)
    assert len(tracks) <= 2, "more than two note tracks"
    for track in tracks:
        groups = collections.defaultdict(list)
        for note in notes:
            if note["track"] == track:
                groups[round(note["on"] * 4)].append(note)
        starts = sorted(groups)
        for i, start in enumerate(starts):
            ends = {round(n["off"] * 4) for n in groups[start]}
            assert len(ends) == 1, "unequal chord lengths"
            assert i + 1 == len(starts) or max(ends) <= starts[i + 1], "overlapping voices"
    for key in ["pdfURL", "lilypondURL", "sourceURL", "licenseURL"]:
        subprocess.run(["curl", "--silent", "--show-error", "--fail", "--location", "--head", "--max-time", "30", piece[key]], stdout=subprocess.DEVNULL, check=True)
    return piece["id"] + ": verified MIDI, checksum, notation constraints and links"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.download_dir.mkdir(parents=True, exist_ok=True)
    root = pathlib.Path(__file__).resolve().parents[1]
    catalog = json.loads((root / "Sources/PianoCatalog/Resources/mutopia.json").read_text())
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(lambda piece: validate(piece, args.download_dir), catalog["pieces"]):
            print(result, flush=True)
    print(f"Validated {len(catalog['pieces'])} editions at source revision {catalog['sourceRevision']}.")


if __name__ == "__main__":
    main()
