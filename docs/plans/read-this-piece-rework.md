# Read this piece: fixing a misread piece (rework plan)

Status: **plan for review**. Nothing here is implemented yet.

## The flow today

Books tab (macOS only, `#if os(macOS)`):

1. **Pick**: `BookPagePicker` (`Sources/PianoPad/BooksView.swift:139`). Click a line, Shift-click the last line, then **Read this piece** (`BooksView.swift:241`, calls `BookImportModel.read()`).
2. **Read**: `BookImportModel.read()` (`Sources/PianoPad/BookImportModel.swift:233`) crops each system. `readSystem` measures noteheads (`NoteheadGeometry.measure`) and asks Muse Wonder for a `SystemReading`. Readings are cached by image hash in `ReadingCache/` (`cachedReading`, `:332`).
3. **Merge**: `finishReading` (`:289`) runs `BarMerge.merge` (`Sources/PianoAI/BarMerge.swift:89`). Where the head count matches the notes read, a bar is *trusted* and takes the measured positions; otherwise it is *flagged* for review.
4. **Review / correct**: `ReviewView` + `BarCard` (`BooksView.swift:299`, `:372`). Each card has:
   - **Listen**
   - **That's right** (`confirm`)
   - ↑/↓ per note (`nudge`, `:381`)
   - **Fix this bar** (`fix`, `:412`), which re-reads just that bar with the model.
5. **Save**: `save()` (`:481`) runs `ScoreWriter.write` → `Imported/<slug>/piece.mid|musicxml|score.json|piece.json` (`BookLibrary.swift`), then opens Practice.
6. **Correct later**: sidebar context menu **Read again…** (`readAgain`, `:535`) goes back to the page with the lines selected.

## How I tested

- Ran `swift test --filter 'PianoAITests|PianoPadTests'`. Everything passes, but **nothing tests the review/correction model** (`BookImportModel` has one test, about missing keys).
- Wrote throwaway repro tests (not committed) for the pure-logic bugs. Four of them failed as predicted (B6, B7, B8, B12 below).
- Ran a debug build of the app against the real data in `~/Library/Application Support/PianoPad` (Starter Book, page 1) and drove the Books tab. Cost: one real Muse Wonder read of line 2.

## Bugs found

Severity: **S1** crash or data loss, **S2** blocks correcting a piece, **S3** wrong result shipped silently, **S4** polish.

| # | Sev | Bug | Where | How confirmed |
|---|-----|-----|-------|---------------|
| B1 | S1 | **Cancel while reading crashes the app.** `startOver()` empties `reads`, then the in-flight `readSystem` writes `self.reads[id]` → index out of range. Even without a crash, `finishReading` would then run on an empty `reads`, jump to `.review` with no bars, and could write a stale result into a new read. | `BookImportModel.swift:271-274, 283-285, 471-476, 253-260` | **Reproduced in the app**: crash report `PianoPad-2026-11-01-222056.ips`, `Array subscript` trap at `BookImportModel.swift:272`. |
| B2 | S2 | **No way back into review for a saved piece.** "Read again…" selects the lines, but because a saved piece exists the button becomes **Open saved piece** and simply reopens it. The only escape is the "Ask Muse Wonder again" toggle, which pays for a fresh read of every line, needs a key, and discards everything. | `BooksView.swift:238-244`; `BookImportModel.swift:234-237, 535-543` | **Seen in the app** (line 3: only "Open saved piece" offered). |
| B3 | S2 | **The learner's corrections are never stored.** Nudges, confirmations and re-read bars live only in memory (`bars`). The saved piece keeps the flattened `score.json`, and `ReadingCache` keeps the *original* misreading. Any re-review starts from the wrong notes again. | `BookImportModel.swift:75, 481-503, 331-346` | Code + on-disk check (`Imported/*` holds no review state). |
| B4 | S2 | **Clicking a bar on the page image does nothing**, so a bar the measurement wrongly *trusted* can never be opened to correct. Same `.offset` hit-testing mistake that was fixed in the picker (comment at `BooksView.swift:211-214`): here `.offset(x:)` comes *before* `.contentShape`/`.onTapGesture`. | `BooksView.swift:339-346` | **Seen in the app**: clicks on bars 1 and 5 (both staves) opened no card. |
| B5 | S2 | **A card disappears after the first nudge.** Cards show only for `needsReview || id == selected`. A nudge sets `.nudged`, so the card vanishes while the bar may still have more wrong notes, and B4 means it can't be reopened. "That's right" behaves the same way, and there is no undo or un-confirm. | `BooksView.swift:362, 395-396`; `BookImportModel.swift:376-391` | Code (no flagged bar was available in the test piece). |
| B6 | S3 | **A re-read bar can be trusted in the wrong clef.** `fix()` sends a crop with no clef or key signature, and takes the clef from the model's reply. The heads still match in count, so the bar is marked `.fixed` (trusted) while every pitch is wrong (e.g. treble read as bass gives E3 instead of C5). | `BookImportModel.swift:425-451`; `BarMerge.swift:109-135` | **Repro test failed**: wrong-clef bar `isTrusted == true`. |
| B7 | S3 | **Accidentals don't carry through the bar** in MIDI, Listen or the nudge preview. An F♯ followed by an unmarked F plays F♮. (`altered` is tracked only to decide what to *print*.) | `ScoreWriter.swift:41-52`; `BookImportModel.swift:388-389, 402` | **Repro test failed**: `[66, 65]` instead of `[66, 66]`. |
| B8 | S2 | **Accidentals are invisible and can't be edited.** Note chips use `BarMerge.Note.name`, which drops the accidental (C♯4 shows as "C4"), and the card only offers ↑/↓. A misread sharp, flat or natural can't be seen or fixed. | `BarMerge.swift:63-65`; `BooksView.swift:434-451` | **Repro test failed**: `"C4"` instead of `"C#4"`. |
| B9 | S2 | **Rhythm can't be corrected at all**: no duration or dot change, no rest↔note, no adding or deleting notes, no clef change. A count mismatch ("extra note", "missing note") can only be fixed by Fix this bar (model, key needed) or by confirming wrong music. | `BooksView.swift:372-451`; `BookImportModel.swift:376-391` | Code. |
| B10 | S3 | **Fix this bar silently throws away the learner's nudges** and resets a confirmed bar. It replaces `rb.bar` wholesale. | `BookImportModel.swift:448-451` | Code. |
| B11 | S3 | **A late Fix result can land in the wrong piece.** `fix` tasks aren't cancelled on Start over or a new read. Bars are matched by number only, so bar *N* of the next piece gets overwritten. | `BookImportModel.swift:433-462, 465-469` | Code (same class as B1). |
| B12 | S3 | **Saving a correction under another name duplicates the piece, and similar names collide.** The folder is `slug(title)`, so: renaming on re-save leaves the old folder, and `savedForSelection` picks one of them arbitrarily; "Exercise 1, part A" and "Exercise 1 part A" share a folder; an empty slug becomes "Piece" for everything. | `BookImportModel.swift:487, 549-553`; `:187-193` | **Repro test failed** (collision). |
| B13 | S3 | **Corrections don't reach lessons.** The lesson plan, Learn page, progress and marks are keyed by piece folder (`PieceLessonStore.key`) and only checked against the planner version. Re-saving corrected notes keeps the old plan and steps built from the wrong notes. | `PieceLessonStore.swift:18-38`; `BookProgress.swift:40-48` | Code. |
| B14 | S2 | **A failed read leaves you stuck.** If any line fails (other than a missing key), the phase stays `.reading` with a message and no Retry. Good lines can't be kept. | `BookImportModel.swift:296-299`; `BooksView.swift:257-284` | Code. |
| B15 | S4 | **The engraving is a 210 pt nested scroller.** Bars 5–8 of an 8-bar line sit below the fold inside the card, so "All bars checked" is easy to accept without seeing half the music. | `BooksView.swift:356-360` | **Seen in the app.** |
| B16 | S4 | **"Ask Muse Wonder again" stays on** for every later read in the session (cost surprise). | `BookImportModel.swift:88`; `BooksView.swift:244` | Code. |
| B17 | S4 | **The name isn't filled in from the page heading** on the Starter Book ("Exercise No. 13" and "Hot Cross Buns" became "…, page 1, line 2/3"). | `BookImportModel.swift:201-227` | **Seen in the app.** |
| B18 | S4 | **A dropped crop misnumbers lines.** `read()` uses `enumerated()` + `compactMap`, so one failed crop leaves `reads[id]` misaligned with ids (wrong row updated, or a crash). | `BookImportModel.swift:242-247` | Code. |
| B19 | S4 | **Printed fingering read by the model is discarded.** `ImportedPiece.fingering` is never saved. | `ScoreWriter.swift:61`; `BookImportModel.swift:486-495` | Code. |

Known limits, not bugs (stated in code, out of scope here): no key signatures (`ScoreWriter.swift:14`), no chords or second voices in `SystemReading`, no ties.

## Root causes

1. **There is no document for the correction.** Review state is a transient `[ReviewBar]` on a view model. Saving flattens it to a `Score`. Everything downstream (cache, lessons, re-review) sees either the raw misreading or a black box. → B2, B3, B10, B13.
2. **Async work isn't tied to the session that started it.** Unstructured `Task`s write into arrays by index. → B1, B11, B18.
3. **The editor is only a confirmation dialog.** It offers pitch ±1 and yes/no; anything else depends on the model. → B5, B8, B9, B6.
4. **Pitch semantics live in three places** (`ScoreWriter`, `listen`, `nudge`) and none of them applies the bar's accidental rule. → B7.

## Plan

Each phase is a separate PR against `hackathon`, small enough to review alone, and leaves the app working.

### Phase 0: Stop the crash (hotfix, ~½ day)

- Give each read a `readID: UUID`. `readSystem` / `finishReading` / `fix` capture it and drop their results if `self.readID` changed. Keep the `Task` handles and cancel them in `startOver()`, `read()` and `open()`.
- Look up by `id` instead of by index (`reads.firstIndex { $0.id == id }`). Build `reads` with contiguous ids after `compactMap`.
- Put `@MainActor` on `BookImportModel` so writes are serialized by the compiler rather than by `MainActor.run` sprinkled through the code.
- Fixes **B1, B11, B18**.
- *Done. As built:* `@MainActor` went on the task bodies and the two update helpers, not the whole class: isolating the class spreads to `PlaySession` and `Usage`, which aren't isolated. No session protocol was needed either: tests use `PlaySession(startServices: false)`, as other tests do. Seams: `measureLine`, `readLine`, `barReader`, `startReading(_:)`.

**Tests**
- New `BookImportModelLifecycleTests`. Inject a fake `SystemReader` (add a `readerFactory` seam; `cachedReading` already accepts `reader:`) that suspends on a continuation. Call `read()`, then `startOver()`, then resume, and assert there's no crash, `phase == .choosing`, and `bars` is empty. Same for a stale `fix()` completing after a new `read()`.
- `BookImportModel` needs a `PlaySession?` today. Make the session optional, or a small protocol (`previewPitch`, `previewNotes`, `loadReference`, `tab`), so tests can build the model headless.

**Manual**: read an uncached line, press Cancel mid-read, and confirm the app survives and the picker is usable. Read again and press Start over while a bar is re-reading.

### Phase 1: Correct pitch semantics (~½ day)

- One function, `BarMerge.Bar.midiPitches(staff:)` (or `StaffPitch` with an `altered` state), applies "an accidental lasts to the end of the bar on that line or space". `ScoreWriter`, `listen` and `nudge` all use it.
- `BarMerge.Note.name` (or a new `displayName`) includes the accidental. It is used by the chips.
- Fixes **B7**, and the display half of **B8**.
- *Done. As built:* `BarAccidentals` (in `SystemReading.swift`) tracks what's in force in a bar. `Bar.midiPitches(_:)` and `Bar.noteNames(_:)` are built on it and used by `ScoreWriter`, Listen, the nudge preview and the note chips. Muse Wonder often marks plain notes "natural" rather than "none", so a ♮ is shown only when it cancels an earlier sharp or flat, matching what `ScoreWriter` prints.

**Tests**: F♯ then F gives 66, 66. A natural cancels. A sharp in another octave doesn't carry. The next bar resets. Chip name "C♯4". Re-run `testNaturalsArePrintedOnlyToCancel` and the Beyer fixture tests unchanged.

### Phase 2: A stored correction document (~1½ days; the core of the rework)

Add a `PieceCorrection` (Codable, in `PianoAI` so it is testable without AppKit), saved as `Imported/<id>/review.json` beside `score.json`:

```
PieceCorrection {
  version
  source: { book, bookFingerprint (size+mtime, like BookCache), page, firstLine, lastLine,
            systemImageHashes: [String] }   // ties it to ReadingCache entries
  bars: [ { system, pageBar?, bar: BarMerge.Bar (Codable), resolution, edited: Bool,
            original: BarMerge.Bar } ]
}
```

- `BarMerge.Bar` / `Note` / `Status` and `NoteheadGeometry.Head` become `Codable`. Alternatively, store only `SystemReading.Note` + clef, and keep `head` transient.
- `save()` writes `review.json` alongside the score. The `Score`, MIDI and MusicXML stay derived outputs, regenerated from `bars` on every save.
- **Edit saved piece** (replaces "Read again…" and the "Open saved piece" dead end):
  - It loads `review.json` and goes straight to `.review`. No model call and no key needed.
  - It needs page crops only for the images. If the book is missing, review still works without the page strip.
  - Pieces saved before this change have no `review.json`. Fall back to the cached readings (`ReadingCache`, free) and run `BarMerge` again. Show a one-line note that earlier hand corrections weren't kept.
- Keep a separate **Read again from scratch** action, which asks to confirm because it replaces corrections. It is the only path that uses `freshRead`, and `freshRead` resets after each read (**B16**).
- Stable identity: piece `id` = a slug of book + page + lines (unique per selection), with `title` stored separately. Renaming no longer moves the folder, and duplicates for the same lines can't happen. Migrate old folders on load: if two exist for the same lines, keep the newest and leave the other alone, flagged in the sidebar.
- Fixes **B2, B3, B12, B16**.
- *Done. As built:*
  - Each line's image is saved with the piece (`line-N.png` beside `review.json`), so **Check and correct** needs neither the book nor the page cache.
  - Folders for new pieces are named from the book, page and lines (`BookLibrary.pieceID`). Saving the same lines again reuses whatever folder already holds them, old title-named ones included, so lesson progress stays put and nothing needs migrating.
  - Pieces saved before this change are checked from their saved readings only, never Muse Wonder. If a saved reading no longer matches (the page has been scanned again since), the learner is told to use **Read again from scratch**.
  - **Read again from scratch…** asks first.
  - The name can be changed in the review header.
  - Not done: flagging two folders for the same lines in the sidebar (the newest is used).

**Tests**
- Round-trip `PieceCorrection` encode/decode.
- `save` → `editSavedPiece` reproduces the same bars, resolutions and score bytes.
- A legacy piece without `review.json` falls back to the cached reading.
- Two titles that differ only in punctuation get separate folders.
- Renaming keeps the folder.
- Use a temp `BookLibrary.support` override; add one like `PieceLessonStore.rootOverride`.

**Manual**:
1. Read, nudge a note, save, quit.
2. Relaunch → Edit saved piece shows the nudge.
3. Rename and save: still one sidebar entry.
4. Repeat with a piece saved before this change.

### Phase 3: A real bar editor (~2 days)

Rework `ReviewView` / `BarCard` around a selected bar rather than a filtered list.

- **Selecting**:
  - Fix the page-strip hit testing: `.contentShape(...)` / `.onTapGesture` before `.offset`, as in `BookPagePicker`.
  - Clicking a bar in the engraving also selects it (`NotationView` already knows its measures).
  - Arrow keys or Next/Previous flagged bar. Fixes **B4**.
- **The card stays open** while its bar is selected. The flagged list becomes a "to check" navigator, not the only way to reach a bar. Fixes **B5**.
- **Edit operations** on the selected note, each a pure function on `BarMerge.Bar` in `PianoAI`:
  - pitch ±1
  - accidental cycle (none/♯/♭/♮)
  - duration (whole…sixteenth) and dot
  - note↔rest
  - insert note after / delete note
  - staff clef for the line
- **Bar totals**: show the bar's length against the time signature (e.g. "3½ of 4 beats"), so rhythm mistakes are visible. Fixes **B9** and the edit half of **B8**.
- **Undo/redo**: a model-level stack of `bars` snapshots, wired to ⌘Z/⇧⌘Z. Plus **Revert bar** (back to `original`) and **Un-confirm**. Fixes **B5**.
- **Engraving** shows the whole line without an inner scroller (wrap at a measured width, or height from the line count). Fixes **B15**.

*Done. As built:*
- Edits are plain functions on `BarMerge.Bar` (`BarEdits.swift`). The open bar and the picked note live in the model (`selectedBar`, `selectedNote`).
- Every change to the bars can be undone: edits, clef, That's right, Mark to check, Revert, and a Fix result. Undo/Redo are in the header (⌘Z / ⇧⌘Z); ⌘[ and ⌘] step through bars.
- Clicking a bar in the engraving opens it; the engraving isn't highlighted, because "focus" draws a "★ focus" label.
- The accidental button skips a natural that would cancel nothing: Muse Wonder marks most plain notes "natural".

**Tests**
- Unit tests for each edit function: duration change updates bar length; deleting the last note leaves an empty bar that `ScoreWriter` fills with a rest; accidental cycle; clef change keeps positions.
- Undo stack: edit, undo, redo, and a new edit clears redo.
- Selection: tapping engraving measure *k* selects bar *k*.

**Manual**:
1. In the in-app test piece (Starter Book p.1 line 2), click each of the 8 bars on the page strip and in the engraving, and check that the right card opens.
2. Nudge twice in one bar: the card stays open.
3. Change a quarter to a half and see the beat total update.
4. Undo everything with ⌘Z.
5. Listen after each edit.

### Phase 4: Safer "Fix this bar" (~1 day)

- **Keep the clef from the page**: the re-read keeps each staff's clef from the system's first reading (and later, any line-level clef the learner set). Ignore the model's clef for a clef-less crop. Fixes **B6**.
- **Better crop**: send the crop with the system's clef and time-signature region stitched on the left (the first `barEdges[0]` columns), so the model sees context.
- **Propose, don't overwrite**:
  - The re-read is shown as a diff against the current bar, with changed notes highlighted. The learner chooses **Use this** or **Keep mine**.
  - Edited bars are never replaced silently. A re-read result is never auto-trusted: it lands as `needsReview`, with the diff, unless the bar was untouched *and* the measurement agrees.
  - Fixes **B10**.
- **Cache bar re-reads** by crop hash, like system readings, so reopening is free.

*Done. As built:*
- The clefs come from the line's bars (as first read with the whole line in view, or as the learner set them), else from the clefs measured at the start of the line.
- The crop is the start of the line (its clefs and time signature) beside the bar.
- A bar still as first read takes the new reading straight away; Revert brings the first reading back. A bar the learner corrected or checked gets a proposal instead.
- Re-readings are saved by image. **Fix this bar** asks Muse Wonder again; skipped bars re-read during a read use saved re-readings.
- With no key, a saved re-reading is still used; otherwise the learner is told a key is needed.
- In the app, one "high"-effort bar re-read took about 5½ minutes to come back. Worth timing more before tuning the effort.

**Tests**
- Wrong-clef reply on a treble line → bar keeps treble and the correct pitches.
- A fix on an edited bar produces a pending proposal, not a replacement.
- Accepting a proposal applies it and records an undo step.

**Manual**: on a flagged bar, nudge a note, then Fix this bar. A diff appears and your nudge is still there until you accept.

### Phase 5: Reading failures and lessons (~1 day)

- **Partial failure** (**B14**):
  - Failed lines get **Retry** (per line and "Retry failed").
  - Good lines keep their reading.
  - **Review what was read** continues with failed lines shown as empty flagged bars.
- **Lessons follow corrections** (**B13**):
  - Store a `contentHash` of `piece.mid` in `plan.json` / `lesson.json`, and rebuild the plan and Learn page when it changes.
  - For progress: keep it if only pitches changed in bars already passed; otherwise reset steps that cover changed bars. Or, simpler for a first cut: reset progress and tell the learner "Your corrections changed bars 3 and 5; the lesson restarts from bar 3."
- If the piece is open in Practice, reload it after save. `save()` → `practise()` does this today; keep it when saving from Edit.

*Done. As built:*
- A failed read goes back to picking with the lines still selected (from hackathon's read-in-place change). The message has **Try again**, which reads the same lines; the lines already read are saved, so only the failed ones are asked again.
- Not done: checking what was read while some lines failed. A bar can only be read again with the network, and it's the network that failed.
- Saving a piece that was saved before compares old and new scores bar by bar. If any notes changed, that piece's tutor plans, tutor progress and Learn page (all made from the old notes) are forgotten, and Practice says which bars changed. They're made again from the corrected notes the next time it's taught; marked bars stay. Learn-page progress in each learner's history is left as it is.

**Tests**
- Fake reader that fails line 2 of 3 → Retry succeeds → review has all bars.
- `PieceLessonStore` returns no plan when the MIDI hash differs.
- Progress reset rule.

**Manual**:
1. Turn Wi-Fi off mid-read → Retry after reconnecting.
2. Start a tutor lesson on a piece, correct a note in bar 2 and save → the lesson rebuilds and the Learn page shows the new note.

### Phase 6: Polish (optional, ~½ day)

- Title from the heading (**B17**). Debug `suggestedTitle` against the Starter Book PDF and add a fixture test for "Exercise No. 13" and "Hot Cross Buns".
- Save printed fingering (**B19**) into the piece folder and pass it to `PianoFingeringModel` as hints.

**Done. As built:**

- **B17.** The cause wasn't the font-size rule. PDFKit gives the Starter Book's LilyPond text lines boxes about 136 pt tall, reaching from the heading down past the staff, and `selection(for: rect)` only picks a line whose box middle is inside the rectangle, so every line found nothing, not only the two seen. `BookImportModel.heading(on:above:)` now takes the page's text lines (`selectionsByLine`) whose top lies between 2.5 staff spaces above the line's crop and its top staff line, and picks the largest run that has a letter in it, because time signatures (26 pt) are bigger than the heading (20 pt). `BookTitleTests` checks every line of the Starter Book: each first line gets its heading, and the second page's first line (the rest of "Twinkle") gets none.
- **B19.** `PrintedFinger` (staff, quarter, finger) in PianoGraderCore. `ScoreWriter` records every printed finger on both staves (`ImportedPiece.printedFingering`), `store()` saves them as `fingering.json`, and opening a saved piece passes them to `loadReference(printedFingering:)`. `PianoFingeringModel.analyze(score:printed:)` gives them to the solver as anchors, so the book's fingers are kept and the notes around them are fingered to fit (chords, which book readings don't have, are left to the model). Pieces saved before this have no `fingering.json` and get the model's fingering as before, until they're saved again.

## Order and dependencies

```
0 (crash) ─┬─ 1 (pitch) ─┐
           └─ 2 (document) ─ 3 (editor) ─ 4 (fix bar) ─ 5 (failures, lessons) ─ 6
```

- Phase 0 ships first, on its own: it is the only S1.
- Phase 1 is independent and small.
- Phase 2 must land before 3 and 4, because they edit and protect the stored document.
- Phase 3 is the largest visible change. Worth a quick screenshot review with you before polishing.

## Risks

- **Codable migration**. Old pieces have only `score.json`. The fallback to the cached reading covers pieces whose cache entry still exists. Others open as review of an unedited score with no page link, or read-only. Never delete a user's folder during migration.
- **Changing the piece id format** touches `PieceLessonStore` keys, learner history page ids (`"piece-\(piece.id)"`, `BookProgress.swift:44`) and `restoreSavedPiece`. Plan a one-time rename map. Alternatively, keep existing ids and use the new scheme only for new pieces; I'd recommend keeping old ids for this reason.
- **Editor scope creep**. Durations, rests and insert/delete are enough for beginner books. Chords, ties and voices stay out (the reader can't produce them anyway).
- **Model cost**. Phase 4 adds context to bar crops (slightly larger images) but caches re-reads. Net cost should drop because Edit no longer re-reads whole pieces.
- **SwiftUI hit-testing** is easy to regress (it has broken twice). Phase 3 adds a small UI test or snapshot check and keeps the comment from `BookPagePicker`.
- **Testing seams**. `BookImportModel` is AppKit-bound and owns a `PlaySession`. Phase 0's protocol seam is a prerequisite for most automated tests here, and is worth doing even if later phases slip.

## Test plan summary

- **Automated**:
  - New `PianoAITests`: pitch semantics, edit operations, `PieceCorrection` coding, fix-bar clef.
  - New `PianoPadTests`: lifecycle and cancellation with a fake reader, save/edit round trip with a temp support folder, lesson invalidation.
  - Run: `swift test --filter 'PianoAITests|PianoPadTests'`.
- **Manual script** (Starter Book, page 1; uses cached readings, so no key or cost after the first read):
  1. Cancel mid-read.
  2. Read line 2 and click every bar.
  3. Edit pitch, accidental and rhythm; undo.
  4. Fix a bar after editing it.
  5. Save, quit, relaunch, Edit saved piece.
  6. Rename and save.
  7. Open in Practice / Learn and confirm the corrected notes.
