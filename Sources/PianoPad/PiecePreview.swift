#if os(macOS)
import AppKit
import Foundation
import PianoGraderCore
import PianoGraderIO
import SwiftUI

/// Hearing a piece before opening it: a lesson page, a goal song, a piece read from a book.
/// One plays at a time, through the app's piano, and anything else that makes sound (Listen,
/// play-along, opening a piece, another tab) stops it. Its own object, so the progress ring
/// redraws only the preview buttons, not every view watching the session.
final class PiecePreview: ObservableObject {
    /// What's playing: the id its button was given.
    @Published private(set) var playingID: String?
    /// What's being fetched to play (a Music Library piece downloading).
    @Published private(set) var loadingID: String?
    /// How far through it is, 0 to 1.
    @Published private(set) var progress: Double = 0

    private let synth: () -> PianoSynth?
    /// True as a preview starts, false once it stops (the session mutes the microphone).
    private let onActive: (Bool) -> Void
    private var timer: Timer?

    init(synth: @escaping () -> PianoSynth?, onActive: @escaping (Bool) -> Void) {
        self.synth = synth
        self.onActive = onActive
    }

    func isPlaying(_ id: String) -> Bool { playingID == id }

    /// Plays `url` (at `tempo` bpm, nil: the file's own), or stops it if it's the one playing.
    /// False if it couldn't play.
    @discardableResult
    func toggle(_ id: String, url: URL, tempo: Double? = nil) -> Bool {
        if playingID == id { stop(); return true }
        return play(id, url: url, tempo: tempo)
    }

    /// Finds the file first (it may need downloading), then plays it, unless something else
    /// was started or it was stopped meanwhile. `failed` runs if there was nothing to play.
    func play(_ id: String, resolve: @escaping () async -> (url: URL, tempo: Double?)?, failed: @escaping () -> Void) {
        stop()
        loadingID = id
        Task { @MainActor [weak self] in
            let found = await resolve()
            guard let self, self.loadingID == id else { return }
            self.loadingID = nil
            guard let found, self.play(id, url: found.url, tempo: found.tempo) else { failed(); return }
        }
    }

    @discardableResult
    func play(_ id: String, url: URL, tempo: Double? = nil) -> Bool {
        stop()
        guard let synth = synth(), var sequence = try? MIDIFile.read(url: url) else { return false }
        sequence.notes.removeAll { $0.channel == 9 } // no drums on a piano
        if let tempo, tempo > 0 { sequence = sequence.retimed(bpm: tempo) }
        let notes = Self.sequenceNotes(sequence)
        guard let length = notes.map(\.end).max(), synth.playSequence(notes) else { return false }

        onActive(true)
        playingID = id
        progress = 0
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            // The sequencer reports nil once it has run out.
            guard let t = synth.sequencePosition, t < length + 0.1 else { self.stop(); return }
            self.progress = min(1, t / length)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return true
    }

    func stop() {
        loadingID = nil
        timer?.invalidate()
        timer = nil
        guard playingID != nil else { return }
        synth()?.stopSequence()
        playingID = nil
        progress = 0
        onActive(false)
    }

    /// The piece from its first note, after a short breath so the first one isn't clipped.
    static func sequenceNotes(_ sequence: MIDISequence, leadIn: Double = 0.15) -> [PianoSynth.SequenceNote] {
        let start = sequence.notes.map(\.onset).min() ?? 0
        return sequence.notes.map { note in
            PianoSynth.SequenceNote(pitch: note.pitch, velocity: note.velocity,
                                    start: leadIn + note.onset - start,
                                    end: leadIn + max(note.offset, note.onset + 0.05) - start)
        }
    }
}

/// The round play button on a piece's card or row: iris with a stop square while it plays,
/// a ring filling as it goes, a spinner while the file is fetched. `resolve` finds the file
/// when pressed, so cards don't touch the disk (or the network) while drawing.
struct PreviewButton: View {
    @EnvironmentObject private var session: PlaySession
    let id: String
    let title: String
    var size: CGFloat = PP.Size.compact
    let resolve: () async -> (url: URL, tempo: Double?)?

    var body: some View {
        PreviewButtonBody(preview: session.preview, id: id, title: title, size: size, resolve: resolve)
    }
}

private struct PreviewButtonBody: View {
    @ObservedObject var preview: PiecePreview
    let id: String
    let title: String
    let size: CGFloat
    let resolve: () async -> (url: URL, tempo: Double?)?
    @State private var failed = false

    var body: some View {
        let loading = preview.loadingID == id
        let playing = preview.isPlaying(id) || loading
        Button {
            guard !playing else { preview.stop(); return }
            failed = false
            preview.play(id, resolve: resolve) {
                failed = true
                NSSound.beep()
            }
        } label: {
            if loading {
                ProgressView().controlSize(.small).scaleEffect(size < PP.Size.compact ? 0.7 : 0.8).tint(PP.onAccent)
            } else {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .offset(x: playing ? 0 : size * 0.03) // the triangle's weight sits left of centre
            }
        }
        .buttonStyle(PPIconButtonStyle(kind: .mode, isOn: playing, size: size))
        .overlay {
            if preview.isPlaying(id) {
                Circle()
                    .trim(from: 0, to: preview.progress)
                    .stroke(PP.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-4)
                    .animation(.linear(duration: 0.05), value: preview.progress)
                    .allowsHitTesting(false)
            }
        }
        .help(failed ? "Couldn't play \(title)" : (playing ? "Stop" : "Hear \(title)"))
        .accessibilityLabel(playing ? "Stop \(title)" : "Hear \(title)")
    }
}
#endif
