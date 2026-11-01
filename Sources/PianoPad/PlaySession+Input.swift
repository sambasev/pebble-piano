#if os(macOS)
import Foundation
import PianoGraderCore

/// How the learner plays (setup's choice, kept in their settings): applied at launch, when the
/// learner changes, and from the input panel.
extension PlaySession {
    /// The saved choice; nil for learners from before setup asked.
    var chosenInput: InputSource? {
        learnerSettings.inputSource.flatMap(InputSource.init(rawValue:))
    }

    /// Saves the choice and applies it: the microphone on or off, Bluetooth MIDI rescanned.
    func setInput(_ source: InputSource) {
        objectWillChange.send() // the on-screen keyboard shows typing letters only for the computer keyboard
        learnerSettings.inputSource = source.rawValue
        saveLearnerSettings()
        applyInputChoice()
    }

    /// Turns the microphone on for "Microphone" and off for the others. Bluetooth MIDI is
    /// always listened to, so a piano that connects later still plays.
    func applyInputChoice() {
        switch chosenInput {
        case .microphone:
            if !micOn { micOn = true }
        case .midi:
            if micOn { micOn = false }
            startMIDI()
        case .computerKeyboard:
            if micOn { micOn = false }
        case nil:
            break
        }
    }

    /// The Practice tab's Mic switch also changes the saved choice, so it holds after a restart.
    func setMicFromSwitch(_ on: Bool) {
        if on {
            setInput(.microphone)
        } else {
            setInput(midiSources.isEmpty ? .computerKeyboard : .midi)
        }
    }

    /// The header's one-line input status.
    var inputStatusText: String {
        let midi = midiSources.isEmpty ? nil : "Bluetooth MIDI: " + midiSources.joined(separator: ", ")
        switch (micOn, midi) {
        case (true, let m?): return "Mic on · " + m
        case (true, nil): return micName.isEmpty ? "Microphone" : "Mic: " + micName
        case (false, let m?): return m
        case (false, nil): return chosenInput == .midi ? "No Bluetooth MIDI piano" : "Computer keyboard"
        }
    }
}
#endif
