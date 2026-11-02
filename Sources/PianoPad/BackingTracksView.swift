#if os(macOS)
import PianoGraderCore
import PianoLessons
import SwiftUI

/// The Backing Tracks tab: saved tracks on the left, the selected track's editor on the right.
struct BackingTracksView: View {
    @ObservedObject var model: BackingEditorModel
    @ObservedObject var store: BackingStore
    @EnvironmentObject var session: PlaySession

    var body: some View {
        HSplitView {
            sidebar
                .ppGlass(cornerRadius: PP.Radius.xl, padding: PP.Space.s3)
                .tourAnchor(.backingList)
                .padding(.trailing, PP.Space.s2)
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 340)
            Group {
                if model.draft != nil {
                    editor
                        .ppGlass(cornerRadius: PP.Radius.xl, padding: PP.Space.s6)
                } else {
                    VStack(spacing: PP.Space.s4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(PP.onAccent)
                            .frame(width: 64, height: 64)
                            .background(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous).fill(PP.accent))
                            .accessibilityHidden(true)
                        Text("Add a backing track").font(.ppTitle)
                        Text("Import a song to play along with, then mark bar 1, its tempo and where to trim it.")
                            .font(.ppBody)
                            .foregroundColor(PP.inkMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Button { model.importAudio() } label: { Label("Import audio…", systemImage: "square.and.arrow.down") }
                            .buttonStyle(PPPrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ppGlass()
                }
            }
            .tourAnchor(.backingMain)
            .padding(.leading, PP.Space.s2)
            .frame(minWidth: 600)
        }
        .onAppear { session.startTourIfNew(session.currentScreenTour) }
        // The first track opened in the editor has its own tour.
        .onChange(of: model.draft != nil) { editing in
            if editing { session.startTourIfNew(.backingEditor) }
        }
        .foregroundColor(PP.ink)
        .tint(PP.accent)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Backing tracks").ppEyebrow()
                Spacer()
                Button { model.importAudio() } label: { Image(systemName: "plus") }
                    .buttonStyle(PPIconButtonStyle(kind: .tool, size: 28))
                    .help("Import an audio file")
                    .accessibilityLabel("Import an audio file")
            }
            .padding(.horizontal, PP.Space.s1)
            // Selection can be set during a view update; load the track on the next turn.
            List(selection: Binding(get: { model.selectedID }, set: { id in DispatchQueue.main.async { model.select(id) } })) {
                if let draft = model.draft, model.saved == nil {
                    row(draft, unsaved: true).tag(Optional(draft.id))
                }
                ForEach(store.tracks) { track in
                    row(track, unsaved: false).tag(Optional(track.id))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Text("Only markers and tempo are saved. The audio files are never changed.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PP.Space.s1)
        }
    }

    private func row(_ track: BackingTrack, unsaved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.name + (unsaved ? " (not saved)" : "")).font(.ppCallout.weight(.semibold)).lineLimit(1)
            Text(String(format: "%@ · %.0f bpm · %d/%d%@", URL(fileURLWithPath: track.audioPath).lastPathComponent, track.bpm,
                        track.timeSignature.numerator, track.timeSignature.denominator, track.key.map { " · \($0)" } ?? ""))
                .font(.ppCaption).foregroundColor(PP.inkMuted).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            header
            WaveformOverviewView(model: model).frame(height: 36)
            WaveformDetailView(model: model).frame(minHeight: 180, maxHeight: .infinity)
                .tourAnchor(.waveform)
            zoomBar
            transport
                .tourAnchor(.transport)
            Divider()
            HStack(alignment: .top, spacing: 28) {
                markers
                    .tourAnchor(.markers)
                timing
                    .tourAnchor(.timing)
            }
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.ppCallout).foregroundColor(PP.warning)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Name", text: binding(\.name, default: ""))
                .textFieldStyle(.roundedBorder)
                .font(.ppHeadline)
                .frame(maxWidth: 360)
            if let path = model.draft?.audioPath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.ppCaption).foregroundColor(PP.inkMuted).lineLimit(1).truncationMode(.middle)
                    .help(path)
            }
            Spacer()
            Button("Revert") { model.revert() }
                .buttonStyle(PPGlassButtonStyle())
                .disabled(!model.hasChanges || model.saved == nil)
            Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down.on.square") }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.hasChanges)
            Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                .buttonStyle(PPIconButtonStyle(kind: .tool))
                .help("Delete the saved markers (not the audio)")
                .accessibilityLabel("Delete the saved markers")
        }
    }

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Text(String(format: "Cursor %@", Self.time(model.cursor))).monospacedDigit().foregroundColor(PP.inkMuted)
            Spacer()
            Button("Fit") { model.zoomToFit() }
            Button("Bar 1") { model.zoomToBar1() }.help("Zoom in around bar 1")
            Button { model.zoom(to: model.viewSpan * 1.6) } label: { Image(systemName: "minus.magnifyingglass") }
            Slider(value: Binding(get: { -log2(model.viewSpan) }, set: { model.zoom(to: pow(2, -$0)) }),
                   in: -log2(max(2, model.duration))...2)
                .frame(width: 160)
            Button { model.zoom(to: model.viewSpan / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .font(.ppCallout)
        .buttonStyle(PPGlassButtonStyle(height: 28))
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button { model.togglePlay() } label: {
                Label(model.isPlaying ? "Stop" : "Play from cursor", systemImage: model.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PPGlassButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            Button { model.play(fromBar1: true) } label: { Label("Play from bar 1", systemImage: "backward.end.fill") }
                .buttonStyle(PPGlassButtonStyle())
                .help("Starts one bar before bar 1, so you hear the click line up")
            Toggle("Click", isOn: $model.clickOn)
                .toggleStyle(PPChipToggleStyle())
                .help("Metronome on the bar grid, to check bar 1 and the tempo")
            Text("Stop where a bar starts, then use the buttons below to mark it.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
            Spacer()
            // The Pebbles dance to the preview, on its bar grid, so you can see the beat line up.
            if session.showsDancers {
                DancerStrip(beat: previewBeat, isMoving: model.isPlaying, height: 56)
                    .frame(width: 150)
            }
        }
    }

    private func previewBeat(_ uptime: TimeInterval) -> GremlinBeat? {
        guard let q = model.previewQuarter(atUptime: uptime) else { return nil }
        return GremlinBeat.at(quarter: q, barStart: 0, meter: GremlinMeter(model.draft?.timeSignature ?? .common))
    }

    private var markers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markers").ppEyebrow()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Trim start")
                    Text(Self.time(model.draft?.trimStart ?? 0)).monospacedDigit()
                    Button("Set at cursor") { model.setAtCursor(.trimStart) }
                }
                GridRow {
                    Text("Bar 1").foregroundColor(PP.accent).fontWeight(.semibold)
                    Text(Self.time(model.draft?.bar1Seconds ?? 0)).monospacedDigit()
                    HStack(spacing: 4) {
                        Button("Set at cursor") { model.setAtCursor(.bar1) }
                        Button("−10 ms") { model.nudgeBar1(-0.01) }
                        Button("+10 ms") { model.nudgeBar1(0.01) }
                    }
                }
                GridRow {
                    Text("Trim end")
                    Text(model.draft?.trimEnd.map(Self.time) ?? "end of file").monospacedDigit()
                    HStack(spacing: 4) {
                        Button("Set at cursor") { model.setAtCursor(.trimEnd) }
                        Button("Clear") { model.resetTrimEnd() }.disabled(model.draft?.trimEnd == nil)
                    }
                }
            }
            Text("Or drag the markers on the waveform.").font(.ppCaption).foregroundColor(PP.inkMuted)
        }
        .buttonStyle(PPGlassButtonStyle(height: 28))
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tempo and key").ppEyebrow()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Tempo")
                    HStack(spacing: 4) {
                        TextField("bpm", value: binding(\.bpm, default: 100), format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        Stepper("", value: binding(\.bpm, default: 100), in: 20...400, step: 1).labelsHidden()
                        Text("quarter notes / min").font(.ppCaption).foregroundColor(PP.inkMuted)
                        Button("Tap") { model.tapTempo() }.help("Tap along with the music a few times")
                    }
                }
                GridRow {
                    Text("Time signature")
                    HStack(spacing: 4) {
                        Stepper(value: tsNumerator, in: 1...15) {
                            Text("\(model.draft?.timeSignature.numerator ?? 4)").monospacedDigit().frame(width: 20)
                        }
                        Text("/")
                        Picker("", selection: tsDenominator) {
                            ForEach([2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden().frame(width: 60)
                    }
                }
                GridRow {
                    Text("Key")
                    Picker("", selection: Binding(get: { model.draft?.key ?? "" }, set: { v in update { $0.key = v.isEmpty ? nil : v } })) {
                        Text("Not set").tag("")
                        ForEach(BackingTrack.keyNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                }
                GridRow {
                    Text("Count-in")
                    Stepper(value: binding(\.countInBars, default: 1), in: 0...4) {
                        Text("\(model.draft?.countInBars ?? 1) bar(s)")
                    }
                }
                GridRow {
                    Text("Fine-tune")
                    HStack(spacing: 4) {
                        Text("Bar")
                        Stepper(value: $model.calibrateBar, in: 2...999) { Text("\(model.calibrateBar)").monospacedDigit() }
                        Button("starts at the cursor") { model.calibrateTempoFromCursor() }
                            .help("Sets the tempo exactly from bar 1 to this bar")
                    }
                }
            }
            if let track = model.draft {
                Text(String(format: "%d bars from bar 1 to the end · one bar is %.2f s", track.barCount, track.barSeconds))
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }
        }
        .buttonStyle(PPGlassButtonStyle(height: 28))
    }

    // MARK: Helpers

    private func update(_ change: (inout BackingTrack) -> Void) {
        guard var track = model.draft else { return }
        change(&track)
        track.clamp()
        model.draft = track
    }

    private func binding<T>(_ path: WritableKeyPath<BackingTrack, T>, default value: T) -> Binding<T> {
        Binding(get: { model.draft?[keyPath: path] ?? value }, set: { v in update { $0[keyPath: path] = v } })
    }

    private var tsNumerator: Binding<Int> {
        Binding(get: { model.draft?.timeSignature.numerator ?? 4 },
                set: { n in update { $0.timeSignature = TimeSignature(numerator: n, denominator: $0.timeSignature.denominator) } })
    }

    private var tsDenominator: Binding<Int> {
        Binding(get: { model.draft?.timeSignature.denominator ?? 4 },
                set: { d in update { $0.timeSignature = TimeSignature(numerator: $0.timeSignature.numerator, denominator: d) } })
    }

    /// 83.25 → "1:23.250"
    static func time(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%06.3f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}
#endif
