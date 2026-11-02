#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import PianoGraderCore
import PianoGraderIO
import UniformTypeIdentifiers

/// The Backing Tracks tab: import a recording, mark trim points and bar 1, set tempo, time
/// signature and key, check it by ear with a click, and save the metadata. Main thread only.
final class BackingEditorModel: ObservableObject {
    enum Marker: Equatable { case trimStart, bar1, trimEnd, cursor }

    let store: BackingStore

    @Published private(set) var selectedID: UUID?
    /// The track being edited (unsaved changes live here).
    @Published var draft: BackingTrack? {
        didSet { if isPlaying, draft?.audioPath != oldValue?.audioPath || timingChanged(oldValue) { stopPreview() } }
    }
    /// The last saved version, for "unsaved changes".
    @Published private(set) var saved: BackingTrack?
    @Published private(set) var peaks: WaveformPeaks?
    @Published private(set) var loadingProgress: Double?
    @Published var message: String?

    /// Visible part of the waveform, in seconds of the file.
    @Published var viewStart: Double = 0
    @Published var viewSpan: Double = 10
    /// Where "Play" starts and the "here" buttons point (seconds).
    @Published var cursor: Double = 0

    @Published private(set) var isPlaying = false
    @Published private(set) var playhead: Double?
    @Published var clickOn = true
    /// For "Bar N is here (sets the tempo)".
    @Published var calibrateBar = 9

    private var player: BackingPlayer?
    private var playerAudioPath: String?
    private var anchorTimer: Timer?
    /// The preview's timing, for the dancers: when it started and its bar grid.
    private var preview: (anchor: PlaybackAnchor, clock: BeatClock)?
    private var tap = TapTempo()

    init(store: BackingStore) {
        self.store = store
    }

    var hasChanges: Bool { draft != nil && draft != saved }
    var audioURL: URL? { draft.flatMap { store.audioURL(for: $0) } }

    // MARK: Library

    func select(_ id: UUID?) {
        guard id != selectedID else { return }
        stopPreview()
        selectedID = id
        let track = store.track(id)
        draft = track
        saved = track
        peaks = nil
        message = nil
        cursor = track?.bar1Seconds ?? 0
        if let track { loadWaveform(for: track, fit: true) }
    }

    func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a backing track (m4a, mp3, wav, aiff…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAudio(url)
    }

    func importAudio(_ chosen: URL) {
        stopPreview()
        // The sandboxed app can only read the chosen file during this launch, so keep a copy
        // in the library folder. The development build keeps pointing at the original.
        var url = chosen
        if AppEnvironment.isSandboxed {
            do {
                url = try store.library.copyAudioIntoLibrary(chosen)
            } catch {
                message = "Couldn't copy \(chosen.lastPathComponent) into the library: \(error.localizedDescription)"
                return
            }
        }
        let duration: Double
        do {
            let file = try AVAudioFile(forReading: url)
            duration = Double(file.length) / file.processingFormat.sampleRate
        } catch {
            message = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }
        let track = BackingTrack(name: url.deletingPathExtension().lastPathComponent, audioPath: url.standardizedFileURL.path,
                                 duration: duration)
        selectedID = track.id
        draft = track
        saved = nil // new: nothing saved yet
        peaks = nil
        cursor = 0
        message = "Imported. Mark bar 1, set the tempo and time signature, then Save."
        loadWaveform(for: track, fit: true, guessStart: true)
    }

    func save() {
        guard var track = draft else { return }
        track.clamp()
        track.modified = Date()
        do {
            try store.save(track)
            draft = track
            saved = track
            message = "Saved “\(track.name)”."
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func revert() {
        stopPreview()
        draft = saved
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(draft?.name ?? "this track")”?"
        alert.informativeText = "Only the saved markers and tempo are deleted, and passages linked to it are unlinked. The audio file stays where it is."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stopPreview()
        if saved != nil {
            do { try store.delete(id) } catch { message = "Couldn't delete: \(error.localizedDescription)" }
        }
        selectedID = nil
        draft = nil
        saved = nil
        peaks = nil
    }

    // MARK: Waveform

    private func loadWaveform(for track: BackingTrack, fit: Bool, guessStart: Bool = false) {
        guard let url = store.audioURL(for: track) else {
            message = "Can't find the audio file \(URL(fileURLWithPath: track.audioPath).lastPathComponent). Import it again or put it in the library folder."
            return
        }
        loadingProgress = 0
        let id = track.id
        WaveformLoader.load(url, progress: { [weak self] p in
            guard self?.selectedID == id else { return }
            self?.loadingProgress = p
        }, completion: { [weak self] result in
            guard let self, self.selectedID == id else { return }
            self.loadingProgress = nil
            switch result {
            case .success(let loaded):
                self.peaks = loaded.peaks
                if guessStart { self.guessFirstSound(in: loaded.peaks) }
                if fit { self.zoomToFit() }
            case .failure(let error):
                self.message = "Couldn't read the audio: \(error.localizedDescription)"
            }
        })
    }

    /// New imports: put the trim start and bar 1 at the first clear sound.
    private func guessFirstSound(in peaks: WaveformPeaks) {
        let threshold = peaks.peak * 0.08
        guard threshold > 0, var track = draft else { return }
        for i in 0..<peaks.bucketCount where max(-peaks.mins[i], peaks.maxs[i]) >= threshold {
            let t = Double(i) * peaks.secondsPerBucket
            track.trimStart = max(0, t - 0.05)
            track.bar1Seconds = t
            track.clamp()
            draft = track
            cursor = track.bar1Seconds
            return
        }
    }

    var duration: Double { draft?.duration ?? peaks?.duration ?? 0 }

    func zoomToFit() {
        viewStart = 0
        viewSpan = max(1, duration)
    }

    /// Zooms around a time so `span` seconds are visible.
    func zoom(to span: Double, around center: Double? = nil) {
        let c = center ?? (viewStart + viewSpan / 2)
        viewSpan = min(max(0.25, span), max(1, duration))
        viewStart = clampedStart(c - viewSpan / 2)
    }

    func zoomToBar1() {
        guard let track = draft else { return }
        zoom(to: track.barSeconds * 4, around: track.bar1Seconds + track.barSeconds * 1.5)
    }

    func scroll(to start: Double) { viewStart = clampedStart(start) }

    private func clampedStart(_ s: Double) -> Double { min(max(0, s), max(0, duration - viewSpan)) }

    // MARK: Markers

    /// Moves a marker to a time (seconds of the file), keeping them in order.
    func move(_ marker: Marker, to time: Double) {
        let t = min(max(0, time), duration)
        if marker == .cursor {
            cursor = t
            return
        }
        guard var track = draft else { return }
        switch marker {
        case .trimStart:
            track.trimStart = min(t, track.playEnd - 0.05)
            if track.bar1Seconds < track.trimStart { track.bar1Seconds = track.trimStart }
        case .bar1:
            track.bar1Seconds = t
        case .trimEnd:
            track.trimEnd = max(t, max(track.trimStart, track.bar1Seconds) + 0.05)
        case .cursor:
            break
        }
        track.clamp()
        draft = track
    }

    func setAtCursor(_ marker: Marker) { move(marker, to: cursor) }

    func nudgeBar1(_ seconds: Double) {
        guard let track = draft else { return }
        move(.bar1, to: track.bar1Seconds + seconds)
    }

    func resetTrimEnd() {
        guard var track = draft else { return }
        track.trimEnd = nil
        draft = track
    }

    /// Bar `calibrateBar` starts at the cursor: sets the tempo from bar 1 to here.
    func calibrateTempoFromCursor() {
        guard var track = draft, calibrateBar > 1 else { return }
        let seconds = cursor - track.bar1Seconds
        guard seconds > 0.2 else {
            message = "Put the cursor on the start of bar \(calibrateBar), after bar 1."
            return
        }
        let quarters = Double(calibrateBar - 1) * track.timeSignature.quartersPerMeasure
        track.bpm = (quarters * 60 / seconds * 100).rounded() / 100
        track.clamp()
        draft = track
        message = String(format: "Tempo set to %.2f bpm from bar 1 to bar %d.", track.bpm, calibrateBar)
    }

    func tapTempo() {
        guard let bpm = tap.tap(at: ProcessInfo.processInfo.systemUptime), var track = draft else { return }
        track.bpm = (bpm * 10).rounded() / 10
        draft = track
    }

    // MARK: Preview

    /// Plays from the cursor (or from just before bar 1) with the click on the bar grid.
    func play(fromBar1: Bool = false) {
        guard let track = draft, let url = audioURL else {
            message = "The audio file can't be found."
            return
        }
        stopPreview()
        let clock = BeatClock(startSeconds: track.bar1Seconds, bpm: track.bpm, timeSignature: track.timeSignature)
        do {
            let p = try BackingPlayer(annotation: track.annotation(audioPath: url.path), fileURL: url, clock: clock)
            player = p
            playerAudioPath = track.audioPath
        } catch {
            message = "\(error)"
            return
        }
        let start = fromBar1 ? max(track.trimStart, track.bar1Seconds - track.barSeconds) : cursor
        guard let player, start < track.playEnd - 0.05 else { return }
        let anchor = player.play(fromAudioSeconds: start, clicks: clickOn)
        preview = (anchor, clock)
        isPlaying = true
        anchorTimer?.invalidate()
        let end = track.playEnd
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let q = anchor.quarter(atUptime: now)
            let t = clock.audioSeconds(atQuarter: q)
            if now < anchor.uptime { self.playhead = start; return }
            if t >= end { self.stopPreview(); return }
            self.playhead = t
            // Follow the playhead when it runs off the right edge.
            if t > self.viewStart + self.viewSpan * 0.95 { self.scroll(to: t - self.viewSpan * 0.1) }
        }
        RunLoop.main.add(timer, forMode: .common)
        anchorTimer = timer
    }

    /// Where the preview is, in quarters from bar 1, for drawing that moves with it. Not
    /// published; nil when no preview is playing.
    func previewQuarter(atUptime uptime: TimeInterval) -> Double? {
        guard isPlaying, let preview else { return nil }
        return preview.anchor.quarter(atUptime: uptime) - preview.clock.barStart(0)
    }

    func togglePlay() { isPlaying ? stopPreview() : play() }

    func stopPreview() {
        anchorTimer?.invalidate()
        anchorTimer = nil
        preview = nil
        player?.stop()
        player = nil
        if isPlaying { isPlaying = false }
        if let p = playhead {
            cursor = min(max(0, p), duration)
            playhead = nil
        }
    }

    private func timingChanged(_ old: BackingTrack?) -> Bool {
        guard let old, let new = draft else { return true }
        return old.bpm != new.bpm || old.bar1Seconds != new.bar1Seconds || old.timeSignature != new.timeSignature
            || old.trimStart != new.trimStart || old.trimEnd != new.trimEnd
    }
}
#endif
