import Foundation
import PianoGraderCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import PianoGraderIO

enum KeyboardRecorderError: Error, CustomStringConvertible {
    case notATerminal
    case cancelled

    var description: String {
        switch self {
        case .notATerminal: return "Musical typing needs an interactive terminal (stdin is not a TTY)."
        case .cancelled: return "Take cancelled."
        }
    }
}

/// Terminal settings to restore on exit, including on Ctrl-C. Global so the C signal
/// handler can reach it without capturing context.
private var savedTerminal = termios()
private var terminalIsRaw = false

private func restoreTerminal() {
    if terminalIsRaw {
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminal)
        terminalIsRaw = false
    }
}

/// Records a take typed on the computer keyboard, in the Logic/Ableton musical-typing layout.
///
/// Terminals report key presses but not releases, so every note gets a fixed length
/// (`gate`), cut short if the same note is struck again. The grader only uses note
/// onsets in milestone 0, so this does not affect grades. Tap keys rather than holding
/// them: a held key auto-repeats.
final class KeyboardRecorder {
    private var typing: MusicalTyping
    private let gate: Double
    private let sound: Bool

    init(octave: Int = 4, gate: Double = 0.4, sound: Bool = true) {
        self.typing = MusicalTyping(octave: octave)
        self.gate = gate
        self.sound = sound
    }

    func record() throws -> [NoteEvent] {
        guard isatty(STDIN_FILENO) != 0 else { throw KeyboardRecorderError.notATerminal }

        #if canImport(AVFoundation)
        let synth = sound ? PianoSynth() : nil
        #endif

        print("Musical typing — octave \(typing.octave), velocity \(typing.velocity)\n")
        print(typing.diagram)
        print("\nPlay the passage, then press Return.\n")

        try enterRawMode()
        defer { restoreTerminal() }

        var notes: [NoteEvent] = []
        var lastStrike: [Int: Double] = [:]   // pitch → time of last onset, to merge key auto-repeat
        let start = Self.now()

        loop: while true {
            guard let byte = readByte() else { continue } // timed out, keep waiting
            let time = Self.now() - start

            if byte == 0x1B, consumeEscapeSequence() { continue } // arrow keys etc.

            switch typing.handle(byte) {
            case let .note(pitch, velocity):
                // Auto-repeat from a held key arrives every ~30–80 ms: treat as one held note.
                if let last = lastStrike[pitch], time - last < 0.12 {
                    lastStrike[pitch] = time
                    if let i = notes.lastIndex(where: { $0.pitch == pitch }) {
                        notes[i].offset = max(notes[i].offset, time + gate)
                    }
                    continue
                }
                lastStrike[pitch] = time
                // Re-striking a note ends its previous instance.
                if let i = notes.lastIndex(where: { $0.pitch == pitch }), notes[i].offset > time {
                    notes[i].offset = max(notes[i].onset + 0.02, time - 0.005)
                }
                notes.append(NoteEvent(pitch: pitch, onset: time, offset: time + gate, velocity: velocity))
                #if canImport(AVFoundation)
                synth?.play(pitch: pitch, velocity: velocity, duration: gate)
                #endif
                emit(PitchName.of(pitch) + " ")

            case let .octave(octave):
                emit("\r\n[octave \(octave): A = \(PitchName.of(typing.basePitch))]\r\n")

            case let .velocity(velocity):
                emit("\r\n[velocity \(velocity)]\r\n")

            case .finish:
                emit("\r\n")
                break loop

            case .cancel:
                emit("\r\n")
                throw KeyboardRecorderError.cancelled

            case .ignored:
                continue
            }
        }

        guard let t0 = notes.map(\.onset).min() else { return [] }
        return notes.map { n in
            var m = n
            m.onset -= t0
            m.offset -= t0
            m.onsetBeats = m.onset * 2 // takes are saved at 120 bpm
            return m
        }
    }

    // MARK: Terminal

    private func enterRawMode() throws {
        guard tcgetattr(STDIN_FILENO, &savedTerminal) == 0 else { throw KeyboardRecorderError.notATerminal }
        var raw = savedTerminal
        // No line buffering, no echo. Keep ISIG so Ctrl-C still works.
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        // read() returns after at most 0.1 s even with no key, so the loop stays responsive.
        withUnsafeMutablePointer(to: &raw.c_cc) { tuple in
            tuple.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 1
            }
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        terminalIsRaw = true
        signal(SIGINT) { _ in
            restoreTerminal()
            exit(130)
        }
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        return read(STDIN_FILENO, &byte, 1) == 1 ? byte : nil
    }

    /// After an Escape byte: if more bytes follow at once it was an arrow or function
    /// key, so swallow the sequence and return true. A lone Escape returns false.
    private func consumeEscapeSequence() -> Bool {
        guard let next = readByte() else { return false }
        guard next == UInt8(ascii: "[") || next == UInt8(ascii: "O") else { return true }
        while let b = readByte() {
            if (0x40...0x7E).contains(b) { break } // final byte of a CSI sequence
        }
        return true
    }

    private func emit(_ s: String) {
        FileHandle.standardOutput.write(s.data(using: .utf8)!)
    }

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
