import Foundation

// C5: what the app can do and where, for questions about the app itself ("how do I change my
// teacher?", "it can't hear me"). Sent only with questions that look like app help, so music
// questions don't pay for it.

public enum TutorAppGuide {
    /// Bump when the text changes, so eval baselines can tell versions apart.
    public static let version = 1

    public static let text = """
    Pebble Piano guide (v\(version)). Sections in the header: Learn (guided course: unit map,
    lesson pages, ear training and sight reading), Practice (open a piece: score, player, piece
    tutor and this chat), Music Library (public-domain pieces to preview and open), Books (your
    PDF books and pieces read from them), Backing Tracks (link audio to pieces).
    How you play: the input pill in the header (microphone, Bluetooth MIDI piano or computer
    keyboard). Only Bluetooth MIDI devices are listened to; USB and virtual MIDI are ignored.
    Mic learners should calibrate once (about 10 seconds: stay quiet, then play C4, D4, E4);
    the Practice tab's ⋯ menu has Calibrate piano (mic), Measure silence, Clear piano
    calibration, Connect a Bluetooth MIDI piano and Rescan Bluetooth MIDI. Calibration belongs
    to this Mac and piano, so every learner shares it.
    Practice settings (slider icon in Practice): backing track, metronome, mode (note by note
    or play along), on a miss (replay the bar or wait for the note), judge strictness
    (gentle, standard, strict, custom) and fine-tuning. Speed is the tempo strip above the score.
    Teacher: Alex (relaxed) or Kriti (strict), chosen at setup; change it with the Teacher menu
    on the Learn unit map.
    Learners: the avatar menu switches, adds and manages learners (rename, reset progress,
    export a learner's takes and progress as a zip, delete).
    History: every graded take is saved for the active learner; this chat sees recent takes.
    Grading is by the app's grader, never by the tutor.
    """

    static let cues = [
        "app", "setting", "settings", "button", "menu", "where is", "where do", "how do i change",
        "how do i turn", "switch", "mic", "microphone", "hear", "hearing", "detect", "calibrat",
        "midi", "bluetooth", "keyboard", "input", "export", "history", "teacher", "persona",
        "strict", "judge", "backing", "metronome", "learner", "profile", "tab", "marked wrong",
        "wrong when", "played it right", "bug", "not working", "doesn't work", "won't",
    ]

    /// A cheap check: does the question look like it's about the app rather than the music?
    public static func isAppQuestion(_ question: String) -> Bool {
        let q = question.lowercased()
        return cues.contains { cue in
            cue.count <= 4 ? q.split(whereSeparator: { !$0.isLetter }).contains { $0.hasPrefix(cue) } : q.contains(cue)
        }
    }
}
