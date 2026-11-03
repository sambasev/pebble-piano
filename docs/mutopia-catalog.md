# Mutopia catalog review

The bundled index contains 30 solo piano/keyboard editions selected from Mutopia source revision `2144afd6f52d56c5b6995b8b589ef1268b3139f0`.
The MIDI remains unchanged and downloads on demand; each entry pins its SHA-256, exact typesetter credit, edition license and original PDF/LilyPond links. Source headers use either `license` or the older `copyright` field. Public-domain markings here describe the typesetter’s dedication. CC BY files retain their exact license version. Difficulty is editorial guidance, not an examination grade.

Review checks: follow all local LilyPond includes; reject tuplets, pickups and grace notes; parse actual published MIDI; check every onset and offset against the sixteenth grid, piano pitch range, constant metre, at most two note-bearing tracks, equal chord durations and no held note crossing a later onset in the same staff. These constraints avoid known transcription losses. The generated practice score still omits original engraving, fingering, ornaments, articulations and dynamics. Repeats follow the MIDI playback order. Some older Bach collection editions carry historical composer attributions; the catalog labels these as attributed.

## Reviewed editions

| ID | Title | Typesetter | License | MIDI notes | Note tracks |
| --- | --- | --- | --- | ---: | ---: |
| mutopia-219 | La Petite Réunion, Op. 100 No. 4 | Bas Wassink | Public Domain | 395 | 2 |
| mutopia-203 | l'Arabesque, Op. 100 No. 2 | Bas Wassink | Public Domain | 283 | 2 |
| mutopia-214 | Innocence, Op. 100 No. 5 | Bas Wassink | Public Domain | 215 | 2 |
| mutopia-230 | Inquiétude, Op. 100 No. 18 | Bas Wassink | Public Domain | 322 | 2 |
| mutopia-228 | Douce Plainte, Op. 100 No. 16 | Bas Wassink | Public Domain | 261 | 2 |
| mutopia-222 | La Bergeronnette, Op. 100 No. 11 | Bas Wassink | Public Domain | 246 | 2 |
| mutopia-215 | Progrès, Op. 100 No. 6 | Bas Wassink | Public Domain | 213 | 2 |
| mutopia-227 | Ballade, Op. 100 No. 15 | Bas Wassink | Public Domain | 756 | 2 |
| mutopia-1806 | March of the Wooden Soldiers, Op. 39, No. 5 | Anonymous | Public Domain | 318 | 2 |
| mutopia-191 | Menuett | Bas Wassink | Public Domain | 269 | 2 |
| mutopia-2062 | Eight-Measure Exercise, Op. 821, No. 3 | Manuel Castejon Limas | Public Domain | 209 | 2 |
| mutopia-2061 | Eight-Measure Exercise, Op. 821, No. 2 | Manuel Castejon Limas | Public Domain | 112 | 2 |
| mutopia-2060 | Eight-Measure Exercise, Op. 821, No. 1 | Manuel Castejon Limas | Public Domain | 152 | 2 |
| mutopia-2069 | Eight-Measure Exercise, Op. 821, No. 8 | Manuel Castejon Limas | Public Domain | 143 | 2 |
| mutopia-846 | Swedish Folk Dance, Book 3 No. 23 | Erik Sjölund | CC BY 2.5 | 382 | 2 |
| mutopia-882 | Swedish Folk Dance, Book 3 No. 9 | Erik Sjölund | CC BY 2.5 | 266 | 2 |
| mutopia-874 | Swedish Folk Dance, Book 3 No. 17 | Erik Sjölund | CC BY 2.5 | 142 | 2 |
| mutopia-865 | Swedish Folk Dance, Book 1 No. 30 | Erik Sjölund | CC BY 2.5 | 180 | 2 |
| mutopia-821 | Swedish Folk Dance, Book 1 No. 22 | Erik Sjölund | CC BY 2.5 | 428 | 2 |
| mutopia-836 | Swedish Folk Dance, Book 1 No. 14 | Erik Sjölund | CC BY 2.5 | 136 | 2 |
| mutopia-1016 | Polonaise in G minor, BWV Anh. 119 | Steven McDougall | Public Domain | 148 | 2 |
| mutopia-76 | Menuet, BWV Anh. 115 | Allen Garvin | Public Domain | 199 | 2 |
| mutopia-61 | Invention 8, BWV 779 | Allen Garvin | Public Domain | 598 | 2 |
| mutopia-59 | Invention 13, BWV 784 | Allen Garvin | Public Domain | 564 | 2 |
| mutopia-71 | Invention 11, BWV 782 | Allen Garvin | Public Domain | 568 | 2 |
| mutopia-79 | Musette, BWV Anh. 126 | Allen Garvin | Public Domain | 171 | 2 |
| mutopia-78 | Aria, BWV 515 | Allen Garvin | Public Domain | 97 | 2 |
| mutopia-68 | Invention 15, BWV 786 | Allen Garvin | Public Domain | 477 | 2 |
| mutopia-67 | Invention 4, BWV 775 | Allen Garvin | Public Domain | 443 | 2 |
| mutopia-62 | Invention 10, BWV 781 | Allen Garvin | Public Domain | 439 | 2 |

## Refresh and revalidation

Use `python3 scripts/validate_music_catalog.py --download-dir /tmp/mutopia-validation` to fetch and validate the pinned MIDI assets and check LilyPond/PDF links. Then run `MUTOPIA_REVIEW_DIR=/tmp/mutopia-validation swift test --filter CatalogCorpusTests` to validate every asset with the actual Swift MIDI reader and engraver. Network validation is opt-in; ordinary tests use synthetic MIDI and mocked networking. Replacing an asset requires a new review and checksum; existing cached bytes and content-based learner history remain intact.
