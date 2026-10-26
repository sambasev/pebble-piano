# User Journeys

Oct 25, 2026 · Sam

How people move through PerfectPiano, one journey at a time. Each section covers who it's for,
the steps, what data it touches and what's left out of v1.

## 1. Multiple profiles

Several people learn on the same Mac: an adult self-learner (who is also the teacher) and,
later, a child. Each needs their own progress, settings and coach, while the books, annotations
and piano setup are shared.

### Decisions

- **Trust-based switching.** No passwords or parent PIN in v1. Anyone can pick any profile;
  this is a household app and the TestFlight beta is friends and family.
- **Calibration belongs to the device and piano, not the person.** One mic calibration serves
  every profile on that Mac.
- **All graded data is keyed by profile from day one.** Retrofitting ownership onto takes and
  progress later is the expensive part, so it goes in before anything else builds on it.
- **Naming:** the learner type is `Learner`, not `Profile`, because `PianoProfile` already means
  the mic calibration in `PianoGraderCore`.
- **Pieces have stable IDs.** Takes, progress and persona-per-piece are all keyed by a `PieceID`:
  `passage:<id>` for a book passage, `file:<hash>` for a loose MIDI file. Renaming or moving a
  file shouldn't orphan its history.
- **Recent files are bookmarks, not paths.** The sandboxed app can't reopen a file from a path
  saved in an earlier launch, so recent pieces are stored as security-scoped bookmarks.

### Journeys

**1.1 First launch**
1. The app opens with no learners and asks for a name, an avatar, and adult or child.
2. Optionally, a rough level (just starting / knows the basics).
3. If no mic calibration exists and there's no MIDI keyboard, offer the 30-second calibration.
   Skip it if the Mac is already calibrated.
4. Land on that learner's home: recent pieces and what to practise next.

**1.2 Pick who's playing**
1. On launch, show a picker with one tile per learner, plus "Add learner".
2. If there's only one learner, skip the picker and open straight into it.
3. A toolbar avatar menu switches learner at any time. Switching stops the current take,
   saves it to the outgoing learner, and reloads settings for the incoming one. (Until takes
   are stored per learner in Step 4, switching stops the take and discards it.)

**1.3 Practise**
Everything recorded while practising belongs to the active learner: takes, passage progress,
persona choice per piece (Kriti or Alex), strictness, play-along miss mode, recent pieces and
the what-to-practise-next queue.

**1.4 Teacher work**
Annotation mode stays available to adult learners. Annotations are shared: they describe the
passage, not the student, so a correction made while signed in as anyone applies to everyone.
Child learners don't see annotation mode in the menus (hidden, not locked).

**1.5 Child learner**
- Alex is the default persona; Kriti is still available.
- Simpler home: one "Keep going" button into the next passage, fewer settings on screen.
- Shorter session goals.
- The chat tutor runs with a child-safe prompt and no freeform chat.

**1.6 Manage learners**
Rename, change avatar, reset progress, export (takes and progress as a folder) and delete.
Delete asks for confirmation and names what will be lost.

### Shared vs. per-learner data

| Shared (device or library) | Per learner |
| --- | --- |
| Books, licences, passage annotations and overrides | Takes and grading reports |
| Backing-track metadata | Passage progress and completion |
| Mic calibration (`PianoProfile`), mic gate offset | Persona choice per piece |
| Piano and backing volume | Strictness and custom rubric |
| | Play-along miss mode |
| | Recent pieces, coach queue |

### Where the code is today

- Per-learner settings live in global `UserDefaults` keys in `PlaySession`:
  `PianoPad.playAlong.strictness`, `PianoPad.playAlong.custom`, `PianoPad.playAlong.missMode`
  and `PianoPad.recentPieces`.
- Device-wide state stays as it is: `PianoPad.volume.*`, `PianoPad.mic.gateOffsetDB`,
  `piano-profile.json` and `room-noise.json`.
- Takes aren't stored by the app: `saveTake()` only writes one through a save panel. There's no
  passage progress, persona choice or annotation-mode UI yet, so learner history starts with
  this work.

### Implementation plan

Five steps, each its own branch and PR, each leaving the app working.

**Step 0: Merge `testflight`**
- Merge the `testflight` branch (the XcodeGen app wrapper in `App/`, sandbox entitlements,
  `AppEnvironment`) so this work doesn't fork the build.

**Step 1: Learner model and store (no UI change)**
- New library target `PianoPadState` (Foundation only) with its own test target, so the store
  is unit-tested without the app. `PianoPad` depends on it.
- Wire it into both builds: a `.library` product in `Package.swift`, and a dependency entry in
  `App/project.yml` (which lists package products one by one), or the TestFlight archive won't
  link.
- `Learner: Codable, Identifiable { id: UUID, name, avatar, kind: .adult | .child, level?, createdAt }`.
- `PieceID`: `passage:<id>` or `file:<hash>` (see Decisions).
- `LearnerSettings: Codable { strictness, customPlayAlong, missMode, recentPieces }`, with
  defaults matching today's. `strictness` and `missMode` are stored as raw strings, and
  `customPlayAlong` as the JSON-encoded `Rubric.PlayAlong` (`Data?`, `nil` meaning the default),
  so the model doesn't depend on `PlaySession`'s enums or on `PianoGraderCore` (which imports
  Accelerate). `recentPieces` is a list of `RecentPiece { id: PieceID, bookmark: Data, path }`,
  the path kept only for display and as a fallback in the unsandboxed build.
- Add the `com.apple.security.files.bookmarks.app-scope` entitlement in `App/project.yml`.
- `LearnerStore(baseURL:)`: loads and saves `learners.json` with atomic writes; `add`, `rename`,
  `setAvatar`, `delete` (removes the learner's folder), `settings(for:)`, `save(_:for:)`,
  `folder(for:)`. Active learner ID in `UserDefaults` (`PianoPad.activeLearner`), falling back
  to the first learner if it's missing or deleted.
- Layout: `Application Support/PianoPad/learners.json` and `Learners/<id>/settings.json`.
- Tests: round trip, delete removes the folder, active-learner fallback, corrupt or missing
  files load as empty rather than crashing.

**Step 2: Scope settings in `PlaySession`**
- `PlaySession` owns a `LearnerStore` and publishes `learner` and `learners`. The learner code
  goes in a `PlaySession+Learners.swift` extension; `PlaySession.swift` is already ~1,800 lines.
- The four keys above move to `LearnerSettings`; each `didSet` saves the active learner's
  settings instead of writing `UserDefaults`. `rememberPiece`, `forgetPiece` and
  `rebuildPieces` read and write `settings.recentPieces`.
- `switchLearner(to:)`: stop any take, playback and play-along, save, load the new learner's
  settings, `configureJudge()` and `rebuildPieces()`. Mic and calibration are untouched. An
  in-progress take is discarded until Step 4 stores takes.
- Recent pieces resolve their bookmarks (with `startAccessingSecurityScopedResource`) and fall
  back to the path; a bookmark that no longer resolves drops off the list.
- No migration while we're in development: with no `learners.json`, the app starts at
  "Add learner" with default settings, and the old `UserDefaults` keys are ignored.

**Step 3: Profile UI**
- `LearnerPickerView`: avatar tiles plus "Add learner"; shown at launch only when there's more
  than one learner.
- `NewLearnerView`: name, avatar (a small set of SF Symbols or emoji), adult or child, optional
  level.
- Toolbar avatar menu: the other learners, "Add learner…", "Manage learners…".
- `ManageLearnersView` sheet: rename, change avatar, reset progress, delete. Delete confirms and
  names the learner and what's lost; deleting the active learner switches to another one, or
  back to "Add learner" if none are left.
- First launch: after creating the learner, offer the 30-second calibration if no calibration is
  saved and no MIDI source is connected.

**Step 4: Per-learner history**
- Make the grading report `Codable` first; the take summary depends on it.
- Auto-save every graded take to `Learners/<id>/takes/<PieceID>/<timestamp>.mid` plus a
  `.json` summary of the grading report. Keep the existing "Save take…" for exporting a copy.
- `progress.json`: per `PieceID`, attempts, best result, last played and completed. This is what
  the what-to-practise-next coach and the persona-per-piece setting will read later.
- "Reset progress" clears `takes/` and `progress.json` but keeps settings.
- Export: write the learner's folder as a zip through a save panel. `NSFileCoordinator` reading
  with `.forUploading` produces the zip and works inside the sandbox, without shelling out.

**Step 5: Child learners** (moved to M10 in [beginner-journeys-implementation.md](beginner-journeys-implementation.md))
- `kind == .child` gets the simpler home with one "Keep going" button into the next passage,
  using `progress.json` to pick it.
- When annotation mode, personas and the chat tutor land, they read `learner.kind`: annotation
  hidden for children, Alex as the default persona, child-safe chat with no freeform input.
  Until then this step is just the home screen.

**Order**
Steps 0–3 make a shippable beta with profiles. Step 4 is next, since it's what lets the coach
remember where a learner left off. Step 5 waits for personas and annotation mode.

**Before TestFlight**
- The TestFlight build is sandboxed, so Application Support and `UserDefaults` live in the
  app's container and testers start fresh at "Add learner". Nothing to do in code.
- Manual check, on the archived app rather than `swift run`: two learners with different
  strictness and recent pieces, switch mid-take, delete the active learner, relaunch (recent
  pieces still open), and confirm calibration is shared.

### Not in v1

- Parent PIN or passwords.
- Moving takes recorded under the wrong learner.
- Sync between Macs and to iOS (likely CloudKit's private database, with Family Sharing for the
  subscription).
- A limit on the number of learners.
