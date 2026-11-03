#if os(macOS)
import PianoGraderIO
import SwiftUI

/// Input and output pickers. Input defaults to the built-in microphone, output to the system
/// default; both are remembered for this Mac.
struct AudioDevicesView: View {
    @EnvironmentObject var session: PlaySession
    /// Show the output picker too (setup only needs the input before the first sound).
    var showsOutput = true

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: PP.Space.s3, verticalSpacing: PP.Space.s2) {
            GridRow {
                Label("Input", systemImage: "mic").font(.ppCallout)
                PPMenuPicker(title: "Input", selection: $session.inputDeviceUID,
                             current: session.audioInputs.first { $0.uid == session.inputDeviceUID }?.name ?? builtInTitle) {
                    Text(builtInTitle).tag(String?.none)
                    ForEach(session.audioInputs.filter { !$0.isBuiltIn }) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .frame(minWidth: 240)
            }
            if showsOutput {
                GridRow {
                    Label("Output", systemImage: "speaker.wave.2").font(.ppCallout)
                    PPMenuPicker(title: "Output", selection: $session.outputDeviceUID,
                                 current: session.audioOutputs.first { $0.uid == session.outputDeviceUID }?.name ?? defaultOutputTitle) {
                        Text(defaultOutputTitle).tag(String?.none)
                        ForEach(session.audioOutputs) { device in
                            Text(device.name).tag(String?.some(device.uid))
                        }
                    }
                    .frame(minWidth: 240)
                }
            }
        }
        .onAppear { session.refreshAudioDevices() }
    }

    private var builtInTitle: String {
        if let mic = session.audioInputs.first(where: \.isBuiltIn) { return "\(mic.name) (built-in)" }
        return "Default input (no built-in microphone)"
    }

    private var defaultOutputTitle: String {
        AudioDevices.defaultOutput().map { "System default (\($0.name))" } ?? "System default"
    }
}
#endif
