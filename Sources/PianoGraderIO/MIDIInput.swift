#if canImport(CoreMIDI)
import CoreMIDI
import Foundation
import PianoGraderCore

public enum MIDIInputError: Error, CustomStringConvertible {
    case coreMIDI(String, OSStatus)

    public var description: String {
        switch self {
        case let .coreMIDI(step, status): return "CoreMIDI failed to \(step) (status \(status))."
        }
    }
}

/// Listens to MIDI sources and reports note on/off on the main queue. Which sources depends on
/// the `SourcePolicy`: the app listens to Bluetooth MIDI keyboards only; the command-line
/// tools listen to everything. Times are seconds on the system uptime clock, the same clock as
/// `NSEvent.timestamp`.
///
/// CoreMIDI calls the read block on its own high-priority thread, which must not block.
/// The block only decodes the packets and copies each note into a lock-free ring
/// (`RealtimeEventQueue`): no allocation, locks, Objective-C messages, dispatch or reference
/// counting. A worker thread drains the ring and forwards the notes to the main queue.
public final class MIDIInput {
    public typealias NoteOn = (_ pitch: Int, _ velocity: Int, _ time: Double) -> Void
    public typealias NoteOff = (_ pitch: Int, _ time: Double) -> Void

    /// Which MIDI sources to listen to.
    public enum SourcePolicy: Sendable {
        /// Every source (command-line tools, development).
        case all
        /// Bluetooth MIDI devices only: a piano or keyboard paired over Bluetooth. Virtual
        /// ports (Logic's, IAC), USB and network sources are ignored.
        case bluetoothOnly
    }

    /// What kind of source an endpoint is, from its device's driver.
    public enum SourceKind: String, Sendable {
        case bluetooth, usb, network, virtual, other
    }

    public let policy: SourcePolicy
    /// Sources being listened to.
    public private(set) var sourceNames: [String] = []
    /// Sources present but ignored under the policy (e.g. "Logic Pro Virtual Out").
    public private(set) var ignoredSourceNames: [String] = []
    /// Called on the main queue when sources come or go (a keyboard pairs or switches off),
    /// after reconnecting. Passes `sourceNames`.
    public var onSourcesChanged: (([String]) -> Void)?

    /// One note message as read on the MIDI thread. Trivial, so it can go through the ring.
    struct RawNote {
        var hostTime: UInt64
        var isOn: Bool
        var pitch: UInt8
        var velocity: UInt8
    }

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let events: RealtimeEventQueue<RawNote>

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init(policy: SourcePolicy = .all, onNoteOn: @escaping NoteOn, onNoteOff: @escaping NoteOff) throws {
        self.policy = policy
        events = RealtimeEventQueue(capacity: 4096, blank: RawNote(hostTime: 0, isOn: false, pitch: 0, velocity: 0),
                                    name: "PianoGrader.midi-input") { batch in
            // Worker thread: free to allocate and dispatch.
            let notes = batch.map { (note: $0, time: MIDIInput.seconds(hostTime: $0.hostTime)) }
            DispatchQueue.main.async {
                for (note, time) in notes {
                    if note.isOn {
                        onNoteOn(Int(note.pitch), Int(note.velocity), time)
                    } else {
                        onNoteOff(Int(note.pitch), time)
                    }
                }
            }
        }

        // Setup changes (a device paired, unplugged or switched off) reconnect and report.
        // The block can't capture self before init finishes, so it goes through a relay.
        let relay = Relay()
        var status = MIDIClientCreateWithBlock("PianoGrader" as CFString, &client) { notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async {
                guard let input = relay.input else { return }
                input.connectAllSources()
                input.onSourcesChanged?(input.sourceNames)
            }
        }
        guard status == noErr else { throw MIDIInputError.coreMIDI("create a client", status) }

        // The block captures only the poster (a struct of raw pointers), not self.
        let poster = events.poster
        status = MIDIInputPortCreateWithProtocol(client, "PianoGrader input" as CFString, ._1_0, &port) { list, _ in
            MIDIInput.read(list, into: poster)
        }
        guard status == noErr else { throw MIDIInputError.coreMIDI("create an input port", status) }
        relay.input = self
        connectAllSources()
    }

    private final class Relay: @unchecked Sendable {
        weak var input: MIDIInput?
    }

    deinit {
        // Stops the read block before `events` (and its ring) are released.
        MIDIClientDispose(client)
    }

    /// Connects every source the policy allows and disconnects the rest. Runs by itself when
    /// sources change; call it to rescan by hand.
    public func connectAllSources() {
        var names: [String] = []
        var ignored: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            let name = Self.displayName(source)
            if Self.allows(policy, kind: Self.kind(of: source)) {
                MIDIPortConnectSource(port, source, nil)
                names.append(name)
            } else {
                MIDIPortDisconnectSource(port, source)
                ignored.append(name)
            }
        }
        sourceNames = names
        ignoredSourceNames = ignored
    }

    static func allows(_ policy: SourcePolicy, kind: SourceKind) -> Bool {
        switch policy {
        case .all: return true
        case .bluetoothOnly: return kind == .bluetooth
        }
    }

    /// The kind of a source, from the driver that owns its device. A virtual source (one an
    /// app creates, like Logic's) belongs to no device.
    public static func kind(of source: MIDIEndpointRef) -> SourceKind {
        var entity = MIDIEntityRef()
        guard MIDIEndpointGetEntity(source, &entity) == noErr, entity != 0 else { return .virtual }
        var device = MIDIDeviceRef()
        guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else { return .virtual }
        var owner: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(device, kMIDIPropertyDriverOwner, &owner) == noErr,
              let driver = owner?.takeRetainedValue() else { return .other }
        return kind(driverOwner: driver as String)
    }

    /// Apple's drivers: AppleMIDIBluetoothDriver, AppleMIDIUSBDriver, AppleMIDIRTPDriver
    /// (network sessions), AppleMIDIIACDriver (the IAC bus).
    static func kind(driverOwner driver: String) -> SourceKind {
        let d = driver.lowercased()
        if d.contains("bluetooth") { return .bluetooth }
        if d.contains("usb") { return .usb }
        if d.contains("rtp") || d.contains("network") { return .network }
        if d.contains("iac") { return .virtual }
        return .other
    }

    private static func displayName(_ object: MIDIObjectRef) -> String {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr,
              let n = name?.takeRetainedValue() else { return "MIDI source" }
        return n as String
    }

    public static func seconds(hostTime: UInt64) -> Double {
        Double(hostTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// Universal MIDI Packet size in 32-bit words, by message type (top 4 bits).
    @inline(__always)
    private static func packetWords(type: UInt32) -> Int {
        switch type {
        case 0, 1, 2, 6, 7: return 1
        case 3, 4, 8, 9, 10: return 2
        case 11, 12: return 3
        default: return 4
        }
    }

    /// Runs on CoreMIDI's read thread. Realtime-safe: stack values and the ring only.
    private static func read(_ list: UnsafePointer<MIDIEventList>, into poster: RealtimeEventQueue<RawNote>.Poster) {
        for packetPointer in list.unsafeSequence() {
            let stamp = packetPointer.pointee.timeStamp
            let hostTime = stamp == 0 ? mach_absolute_time() : stamp
            let count = min(Int(packetPointer.pointee.wordCount), 64)
            withUnsafeBytes(of: packetPointer.pointee.words) { raw in
                var i = 0
                while i < count {
                    let w = raw.load(fromByteOffset: i * 4, as: UInt32.self)
                    let type = w >> 28
                    if type == 2 { // MIDI 1.0 channel voice message
                        let status = (w >> 16) & 0xF0
                        let pitch = UInt8((w >> 8) & 0x7F)
                        let velocity = UInt8(w & 0x7F)
                        if status == 0x90 && velocity > 0 {
                            poster.post(RawNote(hostTime: hostTime, isOn: true, pitch: pitch, velocity: velocity))
                        } else if status == 0x80 || (status == 0x90 && velocity == 0) {
                            poster.post(RawNote(hostTime: hostTime, isOn: false, pitch: pitch, velocity: 0))
                        }
                    }
                    i += packetWords(type: type)
                }
            }
        }
    }
}
#endif
