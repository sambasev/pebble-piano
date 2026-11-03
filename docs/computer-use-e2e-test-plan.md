# PerfectPiano computer-use E2E test plan

Prepared November 2, 2026; revised after review. This is a plan; no test cases have been executed.

Review decisions: use hackathon source in a separate worktree; make the on-screen piano the primary grader input; add complete feature journeys including book scanning; exercise the real Meta tutor after the user grants Keychain access.

## 1. Scope and baseline

Test the packaged macOS app as a learner uses it: mouse, keyboard, native menus, sheets, file panels, connected piano, and microphone. Exercise complete journeys through input, feedback, grading, saved progress, and relaunch.

Planning evidence:

- Original checkout: `testflight-build` at `dd41eba`, with existing untracked files; left on its original branch. The initial plan used this older source.
- Revised source baseline: separate worktree `/private/tmp/interactive-piano-e2e-plan`, branch `codex/computer-use-e2e-plan`, based on local `hackathon` at `7ab54e2f27721a0551b8245e06e2396d613f8f11` (October 31, 2026). A remote fetch failed because GitHub HTTPS authentication is unavailable; this is the latest locally available hackathon revision, not a verified current remote head. Cached `origin/hackathon` is older (`ede6d2a`). Refresh and record the remote head once authentication is available.
- Hackathon source confirms Learn, Practice, Backing tracks, shared AI settings, and an adaptive piece tutor. The running `com.sambasev.perfectpiano` app also exposes Books, Progress, a screen tour, fingering, and Pebbles. Its exact version/source revision remains unverified. Book scanning is requested coverage but has no import/scan workflow in this local hackathon source; obtain the build/source containing it before claiming execution coverage.
- The running app has an existing learner, microphone input enabled, a Bluetooth MIDI source, and a graded take. Use a separate test environment before changing this state.
- README and design documents contain historical and planned behavior. Use the release's agreed behavior as the oracle; record disagreements between documentation, code, and UI instead of silently choosing one.

Before execution, record the app version/build, source revision if known, app path, signing/sandbox status, macOS version, hardware, display size/scale, input/output devices, and enabled services. Test one explicit build at a time. Do not equate results on the Swift package executable with results on the sandboxed app.

Features observed only in the installed app remain release cases to scope against that build. If absent from the selected build, mark them N/A with a reason; if advertised for that build but inaccessible, report a failure. The requested book-scanning journey remains BLOCKED until a build exposing it is identified; do not replace scanning with opening an already annotated book.

## 2. Execution approach

Use `mcp__cua_repl` for all computer interaction. Prefer named accessibility elements; use screenshots and coordinates for the score, on-screen piano, waveform, and other custom drawing surfaces. Reacquire the accessibility tree after actions before choosing the next target. Recompute coordinates after scrolling, resizing, or changing a score.

The primary grading journey is **click on-screen piano → note recording → Grade → report → export/history**. Microphone input is unnecessary for that path. The source connects `KeyboardView.onPress` to `mouseDown(on:)`, which calls the shared `noteOn` recorder as `.computerKeyboard`; `grade()` sends the recorded take to `Grader`. Test the physical computer-keyboard mappings separately. Turn Mic off through the test learner's input settings and ensure no MIDI device is injecting notes during these runs.

The piano drawing is accessibility-hidden in this source, so use a screenshot to identify key coordinates. Establish the actual visible pitch range and click/hold/release behavior before running the note sequences. Do not infer that a coordinate hit produced the right pitch: assert visible feedback and inspect the exported take.

For each test:

1. Establish and capture the stated starting state, including active learner, piece, input source, mode, tempo, and relevant settings.
2. Perform the actual UI journey. Do not invoke internal app functions or edit progress files to make a journey pass.
3. Assert intermediate states as well as the final outcome. Check text and control state in accessibility data, and inspect graphics in screenshots.
4. Wait for a visible condition with a bounded timeout. Proposed starting budgets: 5 seconds for local UI changes, 15 seconds for small imports, 30 seconds for cold launch. Measure and adjust for the agreed reference machine; these are test budgets, not existing product promises.
5. Capture the result and any persistence check. Export through the UI when the case calls for an export.
6. Restore the test's settings and fixtures. A failed step stops dependent steps, which are marked blocked rather than passed.

Keep filesystem inspection, crash logs, MIDI/XML validation, and performance measurements as supporting evidence. They supplement the UI result and do not replace it.

Do not retry a failing case until it passes and hide the first failure. Preserve the failure; rerun once from a documented clean state to classify reproducibility.

## 3. Environment and fixtures

Use a dedicated macOS test account or disposable test machine. Learner profiles alone do not isolate device-wide calibration, audio settings, or the shared backing library. Preserve the user's existing app data. Request the relevant permission at execution time if OS prompts or irreversible deletion require it; no permission changes are needed to prepare this plan.

Create through the UI:

- `E2E Adult Alex`: beginner, computer keyboard, Alex persona.
- `E2E Adult Kriti`: distinct avatar, Kriti, different judge/miss settings and recent piece.
- `E2E Child`: child journey and parent-facing results.
- A clearly identified disposable learner and backing track for destructive cases.

Prepare a fixture folder and a manifest containing each file's purpose, expected pitches/measures, tempo, duration, and expected result under the selected rubric:

| Fixture | Purpose |
| --- | --- |
| `Examples/five-finger.mid` | Short reference for input, guide, recording, grading, and export |
| New `e2e-eight-notes.mid` and notes-only rubric | Two bars of quarter notes C4 D4 E4 F4 G4 A4 B4 C5, 4/4; exact note-classification assertions from on-screen clicks without requiring a rhythm pass |
| `Examples/take-clean.mid`, `take-wrong-note.mid`, `take-rushed.mid`, `take-skipped-with-warmup.mid` | Existing known takes; useful for controlled MIDI replay and grader cross-checks |
| `Examples/ode-to-joy-c.mid`, `mary-had-a-little-lamb.mid` | Longer score, scrolling, practice, and tutor journeys |
| `Books/learning-the-code-book1.pdf` and annotations; `Examples/ltc-p29-rh-seconds.mid` | Bundled book rendering, passage selection, repeats, and overlays |
| `Lessons/unit1/` | Explain, concept, wait, listen, timed, and song-challenge paths |
| New short chord/repeated-note MIDI | Chord completeness, extra notes, releases, and repeated pitch handling |
| New grand-staff/accidentals/rests/ties/range-extremes MIDI | Notation and hit-test coverage |
| New empty, truncated, malformed, and large MIDI files | Error handling and responsiveness |
| New 30–60-second WAV plus MP3/M4A/AIFF variants | Known bar-1 timestamp, BPM, silence lead-in, and trim boundaries |
| New invalid/empty audio and malformed rubric/annotations | Recoverable import failures |
| Copies with spaces, Unicode, long names, moved paths | Native dialogs, bookmarks, and persistence |
| New synthetic score PDFs/images with independently authored MIDI and expected bar/system boxes | Book scanning: single page, multipage, rotated/low-contrast page, blank page, unsupported file; use known notation and rights-cleared material |

Do not open a take MIDI as the reference and call that a replay test. The app must receive the performed events through its input while the intended reference remains loaded.

Validate fixture expectations independently before using them as an oracle. Existing README expectations for CLI fixtures are useful but are not proof that a UI take was recorded correctly.

## 4. What computer use can verify

| Test type | Method and limitation |
| --- | --- |
| Navigation, setup, settings, exports, persistence | Native computer use; strong visible assertions |
| Grader note accuracy and lifecycle | Primary: click/hold/release the on-screen piano, then Grade; verify exact pitch-error counts, report state, exported take, and learner ownership. No audio input required. |
| Single notes and held notes | Primary: mouse press on a visible piano key with a documented duration; secondary: computer-key `pressKey`; inspect recording and released state |
| Chords and overlapping note releases | Preflight the input capability. The documented computer-use API does not guarantee independent simultaneous note-key down/up. Use a real MIDI keyboard or an explicitly provisioned MIDI replay source when needed; sequential taps are not proof of simultaneity. |
| Rhythm and play-along accuracy | Exercise Start/count-in/miss/pause/replay/resume using on-screen clicks. Check reported timing against actual exported onsets; add a deliberately long internal interval to exercise rhythm feedback. A claimed clean timed performance or exact timing-boundary proof requires preflighted pacing, controlled MIDI replay, or human performance; ordinary computer-use round trips do not provide a precise musical clock. |
| Audio quality, metronome alignment, clipping, stuck sound | Human listening or captured output with an independent audio check; moving UI indicators do not prove correct sound |
| Acoustic note detection | Real piano and microphone, plus controlled playback into a provisioned audio input for repeatable cases. Real-room acceptance remains a separate pass. |
| AI output | Execute a real Meta tutor request through the UI using the existing app-managed Keychain key after user-granted access; verify explanation against local evidence and deterministic exercise state. Add controlled failure-response runs separately. |

If hardware, audio capture, or service control is unavailable, mark those cases blocked with the missing dependency. Keyboard-only testing cannot establish microphone or Bluetooth reliability.

### Concrete grader checks without audio input

Prepare `e2e-eight-notes.mid` and a custom rubric using the public import format: `checks: [notes]`, `notes.min_accuracy: 0.95`, `notes.extra_note_penalty: 0.5`. Import both through native file dialogs. This is an explicit note-only fixture; keep the shipped rubrics for separate timing/integration runs. Set Wait mode, turn automatic grading off, and use manual Grade so an omitted note does not stall the test indefinitely.

For each row, start a fresh take and click the visible pitches in order. Keep distinct attacks farther apart than the rubric's chord window. Inspect the exported take to verify the input really matched the intended sequence before judging an app mismatch.

| ID | Performance through on-screen piano | Expected note result under the test rubric |
| --- | --- | --- |
| GRD-01 | C4 D4 E4 F4 G4 A4 B4 C5 | 8 correct, no errors; Notes passes and overall verdict passes |
| GRD-02 | Substitute F#4 for F4 | 7 correct, 1 wrong pitch; expected F4/played F#4 at m1 b4; Notes and verdict fail |
| GRD-03 | Omit F4; manually Grade after the other seven notes | 7 correct, 1 missed F4 at m1 b4; Notes and verdict fail |
| GRD-04 | Insert F#4 between E4 and F4 | 8 correct, 1 extra; note score 93.75%, below 95%; Notes and verdict fail |
| GRD-05 | Repeat clean run; hold/release a key, Grade, start new take, then discard it | One report per finished take; exported offsets after onsets; discard adds no completed take; no stale notes |
| GRD-06 | Repeat GRD-01 using mapped computer keys A S D F G H J K | Same pitch/count/verdict result as mouse input; timing may differ |

These rows check grading correctness as well as UI wiring. The expected errors are defined by the fixture, not copied from the app's own report. Confirm alignment for these simple fixtures independently; if an insertion aligns ambiguously, redesign the fixture before using it as a release oracle. Do not assert a rhythm pass from note correctness. Use the exported timestamps to assess a deliberately uneven performance, and retain precise timing/chord tests as supporting logic or provisioned-input coverage.

## 5. Prioritized test inventory

P0 = blocks the primary learning/practice journey, loses or misattributes data, or crashes. P1 = required release behavior and significant recovery paths. P2 = extended compatibility and polish. Priorities below describe test importance; classify actual defects by their impact.

### Setup and learners

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| SET-01 | P0 | Fresh launch; complete welcome → learner → piano/input → teacher → goal → ready | One learner created; selected answers applied; first lesson reachable |
| SET-02 | P1 | Back/forward through setup; edit previous answers; cancel Add learner | Answers remain coherent; no premature/duplicate learner; cancel returns safely |
| SET-03 | P1 | Blank/whitespace name, Unicode, long name; edit name/avatar/type | Validations and layout work; valid edits survive relaunch |
| SET-04 | P0 | Relaunch with zero, one, then multiple learners | Setup, direct entry, or learner picker appears appropriately; active identity is clear |
| LRN-01 | P0 | Give two learners different settings/recent pieces; switch repeatedly and relaunch | Per-learner state stays isolated; shared calibration/library remain shared |
| LRN-02 | P0 | Switch learner during recording, audition, count-in, active play-along, and a pending auto-grade | Outgoing activity stops; no delayed report or notes attach to incoming learner; incoming settings apply |
| LRN-03 | P0 | Grade one take as A, another as B; revisit progress/export for each | Each result belongs only to its originating learner |
| LRN-04 | P1 | Export learner using save panel; cancel and repeat successfully | Cancel is harmless; resulting archive is readable and contains that learner's expected data |
| LRN-05 | P0 | Reset disposable learner; cancel first, then confirm | Named consequences are clear; reset removes expected history while retaining settings/recent pieces; other learner unaffected |
| LRN-06 | P0 | Delete disposable inactive learner, active learner, then last learner in isolated environment | Correct identity/consequences; safe fallback to another learner or setup; shared assets retained |

For LRN-02, this checkout discards an unfinished take on learner switch. Assert that behavior unless the selected release specifies saving unfinished takes. Completed, graded results must remain with the correct learner.

### Input and sound

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| IN-01 | P0 | Select computer keyboard, set octave 4; play A/S/D/F/G and a black-key mapping | C4/D4/E4/F4/G4 and expected accidental appear; note-on begins recording; note-off clears held state |
| IN-02 | P0 | Hold one key beyond system repeat delay; release; play again | One sustained note rather than repeated attacks; next attack is accepted; no stuck highlight/audio |
| IN-03 | P1 | Z/X octave, C/V velocity; repeat to boundaries; test Caps Lock and shifted layout | Values remain valid, labels/pitches agree, no out-of-range crash; unsupported layouts documented |
| IN-04 | P0 | Type note letters, Space, Return, Esc into names/BPM fields and open sheets | Text/dialog action works; no accidental music or grading behind the dialog |
| IN-05 | P1 | Mouse-play white/black keys; drag across keys and off the keyboard | Visual hit testing agrees with pitches; previous key releases; drag-out leaves no stuck note |
| IN-06 | P0 | Sound off/on; adjust piano volume; audition and recording | Sound state changes as expected; note detection/feedback continues; no duplicate MIDI synth output |
| IN-07 | P0 | USB MIDI available at launch and attached later; rescan; unplug/reconnect | Source is usable and status accurate; no crash, duplicates, or permanently held notes |
| IN-08 | P1 | Bluetooth connect, disconnect, reconnect and sleep/wake | Appropriate pairing/status; recoverable loss; notes work after reconnect |
| IN-09 | P0 | Mic permission undecided: allow and deny on separate clean runs | Allowed input works; denial is understandable and keyboard/MIDI remain usable |
| IN-10 | P0 | Mic on: quiet room, expected note, wrong note, soft note, chord | Meter/gate and feedback correspond; no quiet-room phantom progression; detection checked against known input |
| IN-11 | P0 | Audition/reference playback with mic enabled, then play a real note | App playback does not grade itself; microphone resumes after playback |
| IN-12 | P1 | Measure silence; adjust gate; switch external input/output; disconnect selected device | Gate/device state is clear and persistent as designed; no crash; fallback/reselection works |
| IN-13 | P1 | Calibrate with C4/D4/E4; retry with wrong/quiet/noisy notes; cancel; clear profile | Success saved/shared; invalid calibration explained; cancel/clear restore usable state |
| IN-14 | P1 | Mic plus MIDI active, same note heard by both; switch saved input choice across learners | Duplicate-input behavior meets release contract; no inflated counts; input choice persists correctly |

### Practice, guide, and grading

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| PRA-01 | P0 | Open bundled reference, use Listen/Space; stop with Space/Esc; repeat at each listen speed | Correct score/key animation; explicit playback state; stop releases notes; no learner take from audition |
| PRA-02 | P0 | Wait mode: wrong note, release, correct note | Guide stays on wrong input, names expected/played note, clears wrong marker on release, then advances once |
| PRA-03 | P0 | Chord reference: partial chord, complete chord, chord plus extra; retry cleanly | Completeness/extra-note rules hold for the selected source; held previous notes handled correctly |
| PRA-04 | P0 | Finish manually using Grade/Return; discard separately using Esc/Start again | Manual finish creates one report; discard does not create a graded success or stale take |
| PRA-05 | P0 | Complete passage, hold last note, release; separately play during pending auto-grade | No grade while held; one grade after configured delay; continued playing cancels/reschedules pending work appropriately |
| PRA-06 | P0 | Auto-grade off; complete passage; manually grade; play after report | No unwanted auto-grade; fresh recording starts on new input with cleared previous take state |
| PRA-07 | P0 | Controlled clean/wrong/missed/extra/rushed performances | Verdict, counts, measure/beat messages, and score markings agree with the independent fixture oracle |
| PRA-08 | P1 | Warm-up/trailing notes and too-short takes | Documented ignored notes/timing-unavailable states; no divide-by-zero, fabricated timing, or crash |
| PRA-09 | P1 | Beginner/Intermediate/custom rubric; invalid rubric import; cancel import | Correct report/rules shown; errors recoverable; existing piece and usable rubric retained |
| PRA-10 | P0 | Play along with linked backing: start, count-in, hit notes, finish | Backing/score/beat stay aligned; correct grading; no recording of count-in as learner notes |
| PRA-11 | P0 | Miss enough notes in Replay bar mode; play replacement attempt | Correct bar replays; final take represents intended last attempts without accumulated duplicate failures |
| PRA-12 | P0 | Miss in Wait for note mode; play wrong then expected note/chord | Playback pauses at correct location, wrong input does not resume, expected input resumes coherently |
| PRA-13 | P1 | Change tempo via preset, stepper, exact BPM during playback | Values agree; restart/current-bar behavior matches release contract; backing and metronome remain synchronized |
| PRA-14 | P1 | Judge presets/custom sliders at limits; miss allowances; reset/persistence | Effective settings and displayed values agree; chosen learner retains them |
| PRA-15 | P0 | Change piece/mode/tab mid-recording, during audition, and pending auto-grade | Old callbacks stop; new reference and expected notes agree; no overlapping transport or stale report |
| PRA-16 | P1 | Start from a selected bar; replay flagged bar; toggle Guide/fingering | Correct location/range; guide and fingering only change intended help; full piece still accessible |
| PRA-17 | P1 | No linked backing, missing backing file, and piece without a reference | Clear unavailable state; disabled or safe actions; Wait remains available where appropriate |

### Scores, books, files, and backing tracks

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| FIL-01 | P0 | More → Open MIDI; choose external valid file; cancel a second import | Correct title/tempo/score; cancel preserves current work |
| FIL-02 | P1 | Import empty/truncated/large MIDI and unusual notation fixtures | Errors recoverable; no misleading old score labeled as new; supported notation readable; limitations recorded |
| FIL-03 | P0 | Open recent external MIDI after quit/relaunch in sandboxed app; move original then reopen | Bookmark behavior matches contract; history remains attached to stable piece identity; failures explained |
| FIL-04 | P1 | Save take and Export MusicXML; cancel, unique filename, then overwrite disposable file | Correct file type/content, pitches/timing or notation; canceled export changes nothing |
| BOK-01 | P0 | Bundled book/passages; Passage/Page views or installed Books tab | Correct page/crop/title; readable score; passage selection loads matching reference |
| BOK-02 | P1 | Correct/wrong notes, ledger lines, repeated passage, graded mistakes on printed page | Overlays align with printed notes; wrong marker clears; repeats reset correctly; measure mapping remains correct |
| BOK-03 | P1 | Open custom annotations/book and malformed/missing assets | Clear supported/unsupported path; failures recoverable. Checkout README explicitly limits custom books in sandbox; verify release expectation. |
| SCN-01 | P0 when available | Books → import synthetic PDF/image → choose page(s) → scan → review → save | Scan progresses to a usable book/passage; recognized notes/bars agree with independent source fixture |
| SCN-02 | P1 | Scan multipage/grand-staff/accidental/repeat fixtures | Page/system/bar order, hand assignment and repeats checked; uncertain or unsupported notation identified |
| SCN-03 | P1 | Scan rotated, low-contrast, blank and malformed inputs | Quality/errors communicated; no empty result presented as successful recognition; retry usable |
| SCN-04 | P0 when available | Edit recognized notes/boundaries using available review controls; save and open in Practice | Corrections retained; score, guide and generated reference agree with corrected content |
| SCN-05 | P1 | Cancel scan; navigate/switch learner mid-request; retry timeout/failure | No stale scan replaces another selection; saved library intact; visible recovery |
| SCN-06 | P0 when available | Save scanned passage → practice through on-screen piano → grade → quit/relaunch | Scan-to-practice path works; saved source/reference/history remain linked and reopenable |
| BAK-01 | P0 | Import known WAV/M4A; wait for waveform; rename and Save | Waveform/duration correct; saved entry exists; original audio unchanged |
| BAK-02 | P1 | Set trim start/bar 1/end; drag markers past each other/bounds; ±10 ms bar-1 nudge | Boundaries remain ordered/valid; numeric values and waveform agree |
| BAK-03 | P1 | Fit/Bar 1 zoom; scroll waveform; seek and preview with Click | Cursor/zoom coherent; preview begins at intended point; click alignment verified by audio |
| BAK-04 | P1 | Set BPM/time signature/key; tap tempo; calibrate known later bar; invalid numeric input | Saved timing corresponds to fixture; invalid values handled without crash or nonsensical playback |
| BAK-05 | P0 | Link saved track to piece; play along; edit/re-save; return to Practice | Correct link and updated timing; only one transport active |
| BAK-06 | P0 | Quit/relaunch; rename/move original audio outside app container | Imported audio still plays in sandboxed build; track and piece link persist |
| BAK-07 | P1 | Revert; change selection with unsaved edits; invalid/large audio; delete disposable linked track | Draft behavior is understandable; stale waveform load cannot replace selected track; missing link safe; original audio retained |

### Lessons, child experience, and history

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| LES-01 | P0 | Unit map → Meet Middle C → explain → wait → listen → timed → results | All block transitions work, expected notes and buttons match each block, next page unlocks legitimately |
| LES-02 | P1 | Meet D, Finger numbers, Adding E, checkpoint, F/G, goal song | Every block type and dependency works; locked pages cannot accidentally bypass prerequisites |
| LES-03 | P0 | Wrong attempts and retries with Alex, then Kriti | Hints/escalation and completion follow selected persona; persona persists per intended scope |
| LES-04 | P0 | Song Listen → Learn → Practise → Perform; repeat after failure; use skip/move-on paths | Stage changes coherent; assistance/skip accounted for; completion/stars match rules |
| LES-05 | P1 | Fail Perform enough to trigger drill; complete notes → slow → full-speed steps | Correct troublesome bar selected; clean-run streak resets on failure; return to full song works |
| LES-06 | P0 | Leave lesson, switch learner, quit/relaunch mid-page; resume | Progress attributed correctly; resume position valid; practice reference restored when leaving Learn |
| LES-07 | P1 | Child learner: Keep going, stickers/cheers, For grown-ups, teacher choice | Child presentation and parent metrics match contract; controls remain reachable; no unintended adult-only feature exposure |
| HIS-01 | P0 | Complete pages/takes; inspect progress and export; relaunch | Attempts, best result, completion, stars, mistakes and timestamps agree with performed work |
| HIS-02 | P1 | Finish for today → summary → Keep going; finish again; switch/quit | One coherent session per sitting; no double-counting; next page correct; idle time excluded as designed |
| HIS-03 | P2 | Idle session and return after break; Warm up/Not now/Review/Continue | Correct idle closure and warm-up offer; no lost/cross-learner position; natural waits scheduled separately |
| HIS-04 | P2 | Multi-day/week-boundary sessions in prepared disposable account | Weekly minutes/days correct for local calendar; no duplicated day or negative duration |

### AI tutor and additional installed-build features

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| AI-01 | P0 | Practice → Teach me this piece → Start assessment → deliberate mistake → Grade → proposed exercise; request Meta explanation | Local evidence selects exercise; live explanation agrees with notes/bars; deterministic controls remain usable |
| AI-02 | P1 | End tutoring/navigate/switch learner during explanation; request again twice | Canceled/stale response cannot overwrite another piece/learner/exercise; no endless loading |
| AI-03 | P1 | Offline, timeout, unavailable/auth/rate-limit service responses using controlled environment | Actionable error, retry possible, local learning/practice still usable; no credentials exposed in UI |
| AI-04 | P1 | Mark bars via Option-click and “Mark the bars I got wrong”; request focused practice | Correct bar set/range used; edits/removal and empty selection handled; printed vs played numbering consistent |
| AI-05 | P1 | AI settings and child profile; inspect outgoing-data explanation and allowed tutor controls | Release's configuration/privacy and child interaction contract honored; no unrequested external submission during testing |
| AI-06 | P0 | Complete local drill; inspect whole-piece progress; Reassess piece; End tutoring | Drill success does not mark full piece mastered; assessment criteria preserved; original full reference/settings restored |
| AI-07 | P1 | Retry, discard and silence during a tutor attempt; inspect saved take/report/`.tutor.json` | No false mastery or stale streak; actual range/speed/input and printed bar mapping recorded consistently |
| UI-01 | P1 | Screen tour: next/back/skip/finish/reopen across sections and window sizes | Anchors match controls, overlays do not trap input, completion state appropriate |
| UI-02 | P2 | Toggle Pebbles during idle/playback/mistakes; repeat with reduced motion if supported | Visual behavior coherent; no interference with notes, transport, or app responsiveness |

AI correctness checks: correct piece identity and available note range; real bar references; advice supported by played mistakes; valid hand/fingering claims for the chosen score; no claim that an unplayed exercise was passed. Do not use exact prose matching as the primary oracle.

The hackathon tutor's practice engine selects assessment → notes/slow/full-speed/context exercises from grading evidence. Meta explains the result and selected exercise; its text must not change grading, transport, exercise selection or completion. Test that distinction explicitly. A missing key or failed request leaves local coaching available; do not require an error banner if this release deliberately falls back silently. Record lack of error clarity separately as a UX finding.

Use the existing Meta credential through the app after the user's promised Keychain access is granted. Source identifies service `com.sambasev.perfectpiano.ai`, account `meta`, and provider base URL `https://api.meta.ai/v1`. These are configuration identifiers, not credential values. Do not extract the key into chat, shell output, a fixture, or a repository. The user handles any required unlock/credential entry; no need to copy the key between environments. If the isolated account cannot access it, use a user-provisioned test credential or a user-approved app environment and record the isolation tradeoff.

Run the tutor journey with synthetic score context and test grading findings sent to Meta, as requested. Inspect the model setting and confirm the app reports a saved key without revealing it. A visible explanation alone could be local fallback: corroborate a successful live response with the app's usage-call/token change or redacted request-status evidence. If the build exposes no distinguishing evidence, report live-service verification as inconclusive. Do not click the broad AI “Run checks” as a substitute for tutor E2E: it also exercises vision/segmentation/transcription outside this text-tutor journey. Credential removal/rotation and broad provider tests are outside this request.

### Layout, recovery, and endurance

| ID | Priority | Computer-use scenario | Expected result |
| --- | --- | --- | --- |
| SYS-01 | P0 | Lose focus while a note sounds; minimize/restore; open sheet; quit with active audio | No permanently sounding note or frozen state; transport outcome consistent with release contract |
| SYS-02 | P1 | Minimum supported window, full screen, resize while score/waveform visible, light/dark/paper styles | Primary actions reachable; no clipped dialog; graphics/hit targets remain aligned |
| SYS-03 | P1 | Keyboard navigation, focus indication, accessible control names/state, VoiceOver spot-check | Core setup/practice/results usable; music feedback not conveyed by color alone; gaps logged |
| SYS-04 | P1 | Cancel all native dialogs, Escape/dismiss sheets, rapid repeated Start/Stop/Grade | No unexpected destructive/default action; no duplicate report or overlapping playback |
| SYS-05 | P1 | Sleep/wake with audio/MIDI; restart app; absent external device | Recoverable transport/input; no crash; persistent state intact |
| SYS-06 | P1 | 45–60-minute mixed session with repeated inputs, imports, learner/tab switches | No sustained UI degradation, growing stuck-note state, crashes, or history corruption |
| SYS-07 | P2 | Corrupt disposable state, unavailable save destination, controlled low-space condition | Clear failure/recovery; no loss of unrelated learners/library; atomic saved state remains readable |

## 6. First executable journeys

Run A–F as the initial smoke, then G–M for complete feature coverage before expanding to the full matrix. Each starts from an explicitly known state. All note-playing steps use the on-screen piano by default, with the computer keyboard as the explicitly named alternate. Physical keyboard mappings are not assumed to be clickable accessibility elements.

**Journey A — fresh learner to first result**

1. Launch in a clean test account. Complete setup as `E2E Adult Alex`, computer keyboard, Alex.
2. Open Learn → Meet Middle C. Continue the first explanation.
3. At the “play Middle C” step, click D4. Assert it does not satisfy C4. Release; click C4. Assert advancement. Repeat once using S/A to cover musical typing.
4. In the three-C wait exercise, click/release C4 three times. Assert progress advances once per strike and completes.
5. Finish remaining wait/listen steps; start the timed block after its count-in. Attempt the notes with on-screen clicks, verify the actual result and retry/help paths. Claim a clean rhythm/stars result only when the actual onsets support it; if completion needs more precise input, record that portion blocked pending provisioned input rather than skipping to a false completion.
6. Check result, next-page state, and learner identity. Finish for today; inspect summary. Quit/relaunch and verify retained progress.

**Journey B — recording and grading lifecycle**

1. Select Practice, computer keyboard input (Mic off), octave 4, Guide on, Wait mode. Import the eight-note reference and notes-only rubric. Disable auto-grade for the manual-finish portion.
2. Click a wrong on-screen piano key, inspect expected/played feedback, then release it. Assert the wrong marker clears and guide has not advanced incorrectly. Discard this exploratory take.
3. Run GRD-01 through GRD-04 as separate takes using on-screen clicks; click Grade. Assert exact counts, bar/beat errors and Notes/overall verdicts from the table. Repeat clean input through computer keys as GRD-06.
4. Save take via UI to the test folder. Independently inspect exported MIDI to confirm recorded pitches/releases.
5. Play again; assert new-take state. Esc; assert discard. Enable auto-grade; replay to completion and release the last note. Assert one report after the configured delay.
6. Repeat while interrupting pending auto-grade with a new note and with a learner change. Assert no stale grading.

**Journey C — learner isolation**

1. As A, choose one recent external piece, judge settings, persona, and input choice. Grade a distinct take.
2. Add B; choose different settings/piece and grade another take.
3. Start an unfinished A take; switch to B. Assert transport stops and incoming values are B's.
4. Inspect/export both histories; verify ownership and no unfinished take on the wrong learner.
5. Quit/relaunch, choose A and B in turn, and repeat the visible checks.

**Journey D — backing import, editing, linking, and sandbox persistence**

1. In the sandboxed app, Backing tracks → Import audio → select the known audio fixture.
2. Name it `E2E Backing`, set known bar 1/BPM/time signature/trim markers and save. Use Fit/Bar 1 zoom, seek, preview with Click and bar-1 ±10 ms nudges; compare timestamps to the fixture and audio alignment independently.
3. Change a marker/name, Revert and verify restoration. Repeat an edit and Save; select another track and back to check draft/selection behavior. Try invalid numeric input and dragging markers past bounds; verify valid ordering and recoverable feedback.
4. Return to Practice; link it to the short reference. Start Play along; inspect count-in/bar progression. Stop, edit/re-save track timing in Backing tracks, return and verify Practice uses the updated timing without overlapping playback.
5. Quit. Move the disposable original audio using Finder, then relaunch. Reopen the same piece and start playback. Assert saved metadata/link and copied audio still work.
6. Import a malformed/empty audio fixture; verify the saved valid track remains accessible. Delete only an explicitly disposable linked track and check clear missing-link recovery while retaining the original source audio.

**Journey E — miss and recovery in play-along**

1. Load known short reference/backing at a slow tempo. Choose explicit judge settings and Replay bar.
2. Deliberately miss one known bar until replay triggers. Verify bar label and reset point.
3. Play it correctly on the retry, then finish. Verify final result/export follows the intended replacement-attempt semantics.
4. Repeat in Wait for note mode. Assert wrong note leaves it waiting; expected note resumes it.
5. Change tempo during playback, stop/restart, then switch tabs. Assert no second audio stream, delayed old notes, or stale playhead.

**Journey F — permission denial remains usable**

1. In an isolated account with undecided microphone permission, select microphone input and deny the OS prompt.
2. Assert visible explanation and no false “listening successfully” state.
3. Select computer keyboard; play and grade a short take.
4. Relaunch; verify no crash/permission-prompt loop. Test granting permission separately through an explicitly approved OS flow.

**Journey G — lesson progression, checkpoint, and remediation**

Preconditions: Alex learner, fresh lesson progress, on-screen piano available; retain actual timed-performance evidence. Covers LES-02 through LES-06.

1. Continue from Meet Middle C into Meet D; inspect unit-map lock/unlock state. Click wrong then expected notes in each explain/wait check.
2. Complete Finger numbers and Adding E; inspect explanations, highlighted pitches and fingering. Leave and reopen mid-block; verify resume position.
3. Open the Au Clair de la Lune checkpoint. Exercise Listen → Learn → Practise → Perform, including Listen stop/restart and a failed timed attempt.
4. Produce two failed Performs; inspect Alex's optional drill offer. Accept it; verify selected bar and notes → slow → full-speed transitions. Check correct/incorrect clean-run streak behavior; use Move on only to test that path, never as evidence of playing cleanly.
5. Repeat key failure/streak transitions as Kriti; verify automatic drill and two-clean-run rule. If precise clean timed input is unavailable, leave that success assertion blocked while still testing failure/retry/navigation.
6. Continue through F/G and the chosen goal song as the build permits. Verify stars, assistance/skip accounting and next-page state. End session, relaunch and verify saved results and reference restoration on returning to Practice.

**Journey H — book import, scanning, review, and practice**

Preconditions: identify the build containing book scanning, its actual control labels and supported source types. In local hackathon `7ab54e2` this journey is BLOCKED, because no scan/import workflow is present. Covers SCN-01 through SCN-06; this is an acceptance journey, not a claim that these controls exist in the inspected source.

1. Open Books and invoke its actual import/scan action. In the native picker, choose a rights-cleared synthetic score with independently known notes, tempo and bar/system positions. First cancel once and verify no partial library entry.
2. Import again; choose a page/range if supported and start scanning. Check progress/busy state and prevent duplicate submissions. Identify the scan service/provider and source-data destination before any external upload; the text-tutor Keychain permission alone does not authorize unrelated scan-service transmission.
3. Review recognized page order, systems, bars, notes, key/time signatures, clefs and repeat play order against the fixture. Exercise available correction controls with one deliberate correction. Log absent correction capability as a limitation rather than inventing a button.
4. Save/title the scanned book or passage. Open it in Practice; verify displayed score, generated reference and guide use the reviewed/corrected music.
5. Click its expected on-screen notes, then try a wrong note and manually Grade. Compare feedback to the independently known score. Export/reference inspection is supporting evidence where the product offers it.
6. Quit/relaunch; reopen saved scan and progress. Verify original imports and corrections remain usable. Repeat with multipage and degraded/rotated fixtures; separately cancel/fail a scan and retry without corrupting saved content.

**Journey I — existing book to passage practice and play-along**

Preconditions: bundled annotated book available, plus an independently checked passage/repeat mapping. Covers BOK-01/BOK-02, PRA-02/PRA-10/PRA-16, FIL-04.

1. Open the bundled book through the build's Books tab or passage picker; choose the known passage. Verify correct page/title, passage crop and full-page switch.
2. Listen to the reference; inspect playhead/key animation. Stop; play the passage through the on-screen piano in Wait mode. Check correct-note overlays and a deliberately wrong note's staff position/release.
3. Follow a repeated passage; verify the guide returns to the correct printed notes and report mistakes map to printed measures rather than an unrelated played-order measure.
4. Grade manually; select/replay an offending bar through available controls. In builds with marked bars, mark/unmark one and inspect the selected range.
5. Link a known backing track and enter Play along. Use Journey E's miss/recovery checks; return to Wait and confirm the same passage remains selected.
6. Save a take/export notation when supported, then relaunch. Verify book selection/history and external-access limitations. This journey validates an existing annotated book and cannot count as scanning coverage.

**Journey J — live Meta tutor from assessment to reassessment**

Preconditions: user has granted app access to the existing Meta Keychain entry; synthetic short piece loaded, on-screen piano enabled, known test learner. Covers AI-01 through AI-07.

1. Open AI settings through the tutor panel. Verify “Saved in the Keychain,” selected Meta tutor model, and baseline usage counts without reading the secret. Close settings.
2. Select Teach me this piece. Verify assessment is initially ready rather than already recording; use Hear it first, stop, then Start assessment. No linked backing track should be required for tutor assessment.
3. After the count-in, enter test notes with a deliberate middle-bar error and Grade. Inspect the deterministic report, local guidance and chosen next exercise/range.
4. Wait for the live explanation. Check it names the actual difficulty and selected exercise and does not invent mastery. Corroborate a live request through usage/status evidence. Invoke What went wrong? and Why this exercise?; verify each stays grounded in the same attempt.
5. Use Learn note by note; click expected notes. Exercise Try again and a discarded attempt. Run available slow/full-speed/context stages; verify actual speed, bars and clean-run progress. A drill pass must not complete the whole piece.
6. Reassess piece and verify full-piece range. End tutoring; verify original reference/mode/tempo restored. Inspect history/export for take, report and tutor context attribution.
7. Repeat a request while changing piece/learner or ending tutoring; old text must not appear in the new context. Test timeout/offline fallback in a controlled environment without deleting the user's key; local coaching and note practice must remain usable.

**Journey K — child learner and grown-up review**

1. Create/select E2E Child; confirm simpler continuation into the next page and expected teacher/goal.
2. Play a wait block with on-screen clicks, make a mistake and retry. Complete an available page; verify encouraging result, stars/sticker and next action.
3. Open For grown-ups and inspect minutes/days, notes/pages learned and the contextual tip against this learner's actual sessions.
4. Change teacher where supported; switch to adult and back. Verify child progress remains separate, UI presentation follows learner kind and device settings remain shared as designed.
5. Finish for today and relaunch; verify Keep going selects a legitimate next/resume page. Check tutor interaction restrictions against this release's actual child contract.

**Journey L — imported piece, progress, export, and recovery**

1. Practice → Open MIDI through native dialog; choose the synthetic or known example copy with a Unicode/spaced filename. Inspect notation, title and reference pitches.
2. Run a short on-screen take, Grade, then retry with an error. Open Progress if available; verify attempts/best/mistakes for the selected learner and piece.
3. Export the take and MusicXML; cancel once before saving each. Export the learner archive. Inspect files independently without treating the UI report as its own oracle.
4. Quit; move the disposable original MIDI in Finder; relaunch and open its recent entry. Verify bookmarks/identity and history survive as specified, or that missing-access recovery is actionable.
5. Try a malformed MIDI/rubric and unavailable save destination. Verify useful failure and a still-playable previous piece. Reset/delete only the explicitly disposable learner, checking cancel before confirm and preservation of other learners/shared assets.

**Journey M — discovery, screen tour, and cross-feature interruption**

1. Open the screen tour where available; exercise Next/Back/Skip/Finish and reopen it. Verify anchors on Learn, Practice, Books and Backing tracks in the selected build.
2. Resize to the supported minimum and full screen; open input/practice settings and native dialogs. Verify primary controls remain reachable and piano/waveform coordinates still match their targets.
3. Start audition, then navigate to Backing tracks and preview the fixture; return to Practice and start Play along. Verify previous transports stop at each transition.
4. Repeat a subset during learner switching, focus loss and window minimize/restore; check no stale grade, stuck visual note or duplicate recording. Independently verify audio where capture/listening is available.
5. Verify keyboard focus and accessible labels on core controls; record custom-canvas accessibility gaps. Toggle Pebbles where available and confirm it does not alter recording/progress.

## 7. Release-specific rule checks

The following values are confirmed in the inspected hackathon source, not automatically in the installed release:

- Wait-mode auto-grade delay: 1.5 seconds after passage completion and all held keys released. Observe it across several runs with tolerance for observation latency; UI polling cannot establish millisecond precision.
- Alex: hint after 2 attempts, teacher escalation after 3, 1 star to move on; drill offered after 2 failed Performs; one clean run per step, at most 4 runs before moving on.
- Kriti: hint after 2 attempts, escalation after 3, 2 stars to move on; automatic drill after 2 failed Performs; two clean runs in a row per step.
- Standard stars: 1 at notes ≥80%; 2 at notes ≥90% and timing ≥0.60; 3 at notes ≥95%, timing ≥0.80, and no help. Missing timing is treated as meeting timing conditions. Check visible help/stars behavior; leave exact numeric boundary proofs to existing logic tests or controlled fixtures.
- Idle closure: 20 minutes, checked by a 60-second timer. Return warm-up: after at least 30 minutes. Schedule natural-wait cases separately; do not change the user's system clock. Any seeded/time-shortened run is supporting coverage and must be labeled as such.

## 8. Coverage matrix and execution order

Avoid the full Cartesian product. Cover each primary input independently, then combine the high-risk pairs: mic + audition; mic + MIDI; learner switch + pending grading; tempo change + replay; backing import + relaunch; child + tutor; sleep/wake + connected device.

| Pass | Scope | Proposed effort, excluding defect fixes |
| --- | --- | --- |
| 0: Baseline and capability check | Refresh hackathon after GitHub auth is available; identify scan-capable build; confirm isolation, fixtures, on-screen key hit testing, AX/screenshots and Keychain/service availability | 30–60 minutes plus unresolved access/build dependencies |
| 1: Primary smoke | Journeys A–F; GRD-01–06 on-screen/typing grade checks; import/export and P0 learner/transport checks | 60–120 minutes with prepared fixtures, excluding precise timed-input setup |
| 2: Functional regression | Journeys G–M and remaining matrix cases; mark scan/live-service/timed-success dependencies explicitly | 3–5 hours plus full lesson completion, scanning and service latency; split into restartable batches |
| 3: Integration | USB/Bluetooth, acoustic mic/calibration, independent audio check, AI success/failure | 2–4 hours plus setup; depends on hardware/services |
| 4: Compatibility and endurance | Supported macOS range, minimum display, permissions, sleep/wake, accessibility, idle/warm-up, soak | Half to one day; long waits can overlap independent preparation |

Run the full core suite on the packaged candidate. If the minimum supported macOS remains 13, include macOS 13 and the current supported macOS on actual available machines. Add Intel coverage only if the release supports Intel. Use a development build for diagnosis and controlled failure injection, then recheck relevant fixes on the packaged candidate.

## 9. Evidence and release gate

Maintain `test-runs/<build>/<run-id>/` or an equivalent artifact location. Record:

- Case ID, priority, build/environment, start state, fixture version, input source, actions, expected and actual results.
- Status: PASS, FAIL, BLOCKED, or N/A; reason and evidence for every non-pass.
- Before/after screenshots for the relevant state, AX excerpts for textual assertions, and action timestamps.
- Exported takes/learner archives/XML where relevant; crash/error logs and audio evidence when needed.
- Bug severity, reproducibility, minimal steps, and the earliest incorrect intermediate state.

Do not record unrelated windows, personal learner data, secrets, or ambient conversations. Use synthetic/disposable test data and targeted captures.

Proposed acceptance gate:

1. All applicable P0 cases pass on the packaged candidate; no unresolved crashes, data loss, cross-learner attribution, or stuck audio.
2. Applicable P1 cases pass or have an explicit reviewed release exception with impact described.
3. Hardware/AI cases promised by the release are executed; blocked integration coverage is a visible release risk, never counted as passing.
   Requested book-scanning coverage must likewise be executed on the identified scan-capable build or remain explicitly blocked; existing-book practice cannot satisfy it.
4. Persistence is verified after real quit/relaunch, including external MIDI bookmarks and copied backing audio.
5. No unexplained inconsistent result across three repetitions of the critical recording/switch/replay journeys.
6. The endurance run completes and remaining limitations are recorded with the build they affect.

The final execution report should give counts by priority/status, defects and evidence links, integration gaps, and a release recommendation. This plan itself makes no claim that the app passes those checks.
