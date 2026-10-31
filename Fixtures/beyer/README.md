# Beyer Op. 101 test fixtures (hackathon)

Ferdinand Beyer, *Vorschule im Klavierspiel*, Op. 101, ed. Ruthardt (Leipzig: Peters, 1895).
Public domain. Scan: IMSLP #81208 (MIT archive scan, cleaned, 600 dpi).

| Folder | What |
|---|---|
| `op101-p24.png`, `op101-p25.png`, `op101-p27.png` | Whole pages at 150 dpi |
| `crops/` | One system per image at 220 dpi: No. 12, No. 13, No. 24 (*Kinderlied*) in two systems |
| `truth/pieces.json` | The answer key: every note of the three pieces, by measure and staff (pitch and duration; no fingering) |
| `modern/` | The answer key re-engraved with Verovio, in the same one-system-per-image layout, plus its MusicXML |
| `midi/` | Reference MIDI made by `scripts/reading_to_midi.py`: `-truth` from the answer key, `-wonder` from Muse Wonder's reading |

**Provenance of the answer key:** transcribed by hand from `crops/` (by Claude), then checked
bar by bar against the printed page by Sam on Oct 31, 2026. Both staves are in treble clef;
the right hand plays C5–G5 and the left hand C4–G4.

`modern/` is drawn from the answer key, so the key is exactly right for those images by
construction.
