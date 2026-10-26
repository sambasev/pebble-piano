import Foundation

/// Where a played note came from. Each source reaches the app with a different delay, so the
/// play-along judge allows each its own extra lateness (`Rubric.PlayAlong`).
public enum InputSource: String, Codable, Sendable, CaseIterable {
    /// A MIDI keyboard: no extra delay.
    case midi
    /// An acoustic piano through the microphone: the detector decides ~70 ms after the strike.
    case microphone
    /// Musical typing or clicking the on-screen keyboard: key-repeat and mouse latency, and no
    /// real key releases (typed notes all last the same time).
    case computerKeyboard
}
