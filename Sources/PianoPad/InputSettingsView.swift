#if os(macOS)
import PianoGraderCore
import SwiftUI

/// The header's input panel, on every tab: how you play, and that input's setup
/// (microphone devices, level and room noise, or the Bluetooth MIDI piano).
struct InputSettingsView: View {
    @EnvironmentObject var session: PlaySession

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("How you play").ppEyebrow()
            VStack(spacing: PP.Space.s2) {
                choice(.microphone, title: "Microphone", systemImage: "mic",
                       detail: "An acoustic or digital piano, heard through the Mac's microphone.")
                choice(.midi, title: "Bluetooth MIDI piano", systemImage: "pianokeys",
                       detail: "A digital piano or keyboard with Bluetooth MIDI. Exact, even with the volume down.")
                choice(.computerKeyboard, title: "Computer keyboard", systemImage: "keyboard",
                       detail: "No piano: type the notes, or click the on-screen keys.")
            }
            Divider()
            switch current {
            case .microphone: microphone
            case .midi: bluetooth
            case .computerKeyboard: keyboard
            }
        }
        .padding(PP.Space.s4)
        .frame(width: 400)
    }

    /// The saved choice, or what's on now for learners without one.
    private var current: InputSource {
        session.chosenInput ?? (session.micOn ? .microphone : (session.midiSources.isEmpty ? .computerKeyboard : .midi))
    }

    private func choice(_ source: InputSource, title: String, systemImage: String, detail: String) -> some View {
        let selected = current == source
        return Button {
            session.setInput(source)
        } label: {
            HStack(alignment: .top, spacing: PP.Space.s3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(selected ? PP.accent : PP.ink)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ppHeadline)
                    Text(detail).font(.ppCaption).foregroundColor(PP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? PP.accent : PP.inkMuted)
            }
            .padding(PP.Space.s3)
            .background(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous)
                .fill(selected ? PP.accent.opacity(0.12) : PP.surfaceRaised.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Microphone

    private var microphone: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            AudioDevicesView(showsOutput: true)
            Text(session.micOn ? "Play any note: the bar should jump." : "Allow the microphone when your Mac asks.")
                .font(.ppCallout).foregroundColor(PP.inkMuted)
            HStack(spacing: PP.Space.s2) {
                MicMeter(level: session.micLevel, gate: session.micGateLevel)
                    .frame(height: 10)
                if let db = session.gateDB {
                    Text("Gate \(Int(db.rounded())) dB").font(.ppCaption.monospacedDigit()).foregroundColor(PP.inkMuted)
                }
            }
            if let prompt = session.calibrationPrompt {
                HStack(spacing: PP.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(prompt).font(.ppHeadline)
                }
            } else {
                Text(noiseText)
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(session.gateDB == nil ? "Measure room noise" : "Measure room noise again") { session.measureSilence() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .disabled(!session.micOn)
            }
        }
    }

    private var noiseText: String {
        switch session.noiseOutcome {
        case .set(let gate, _)?:
            return String(format: "Room noise measured: notes louder than %.0f dBFS count.", gate)
        case .tooNoisy?:
            return "Too noisy to measure. Turn off a fan or music and measure again, or carry on: the mic judges the room as it listens."
        case .silent?:
            return "Nothing came in from the microphone. Check the input above, and that the Mac may use the microphone."
        case nil:
            return session.gateDB == nil
                ? "Optional: stay quiet for 3 seconds so only real notes count. Without it, the mic judges the room for a moment each time it starts."
                : "Stay quiet for 3 seconds to measure the room again (after moving, or if noise sets off notes)."
        }
    }

    // MARK: Bluetooth MIDI

    private var bluetooth: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            if session.midiSources.isEmpty {
                Text("1. Turn on Bluetooth (or Bluetooth MIDI) on the piano.\n2. Press Connect and choose the piano in the window that opens.")
                    .font(.ppCallout).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PP.Space.s2) {
                    Button("Connect a Bluetooth piano…") { session.showBluetoothMIDIPairing() }
                        .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                    Button("Rescan") { session.startMIDI() }
                        .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                }
            } else {
                Label("Connected: " + session.midiSources.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                    .font(.ppHeadline).foregroundColor(PP.success)
                Text("Play a note: it lights up on the on-screen keyboard.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
            if !session.ignoredMIDISources.isEmpty {
                Text("Not a piano, so ignored: " + session.ignoredMIDISources.joined(separator: ", "))
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }
        }
    }

    // MARK: Computer keyboard

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text("Keys A S D F G H J K play C D E F G A B C; W E T Y U are the black keys. Z and X move the octave.")
                .font(.ppCallout).fixedSize(horizontal: false, vertical: true)
            Text("Timing is judged a little more loosely than with a piano.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
        }
    }
}
#endif
