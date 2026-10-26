#if canImport(CoreMIDI)
import CoreMIDI
import Foundation
import PianoGraderCore

enum RecorderError: Error, CustomStringConvertible {
    case coreMIDI(String, OSStatus)
    case noSources

    var description: String {
        switch self {
        case let .coreMIDI(step, status): return "CoreMIDI failed to \(step) (status \(status))."
        case .noSources: return "No MIDI inputs found. Connect a keyboard over USB or pair it in Audio MIDI Setup → Bluetooth."
        }
    }
}

/// Records notes from every connected MIDI source until the player stops.
/// The take ends `silenceSeconds` after the last note is released.
final class LiveRecorder {
    private let silenceSeconds: Double
    private let maxSeconds: Double
    private let lock = NSLock()
    private var held: [Int: (onset: Double, velocity: Int)] = [:]
    private var notes: [NoteEvent] = []
    private var firstEvent: Double?
    private var lastEvent: Double = 0

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    init(silenceSeconds: Double = 2, maxSeconds: Double = 300) {
        self.silenceSeconds = silenceSeconds
        self.maxSeconds = maxSeconds
    }

    func record() throws -> [NoteEvent] {
        var client = MIDIClientRef()
        var status = MIDIClientCreateWithBlock("PianoGrader" as CFString, &client, nil)
        guard status == noErr else { throw RecorderError.coreMIDI("create a client", status) }
        defer { MIDIClientDispose(client) }

        var port = MIDIPortRef()
        status = MIDIInputPortCreateWithProtocol(client, "PianoGrader input" as CFString, ._1_0, &port) { [weak self] list, _ in
            self?.handle(list)
        }
        guard status == noErr else { throw RecorderError.coreMIDI("create an input port", status) }

        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { throw RecorderError.noSources }
        var names: [String] = []
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(port, source, nil)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr, let n = name?.takeRetainedValue() {
                names.append(n as String)
            }
        }
        print("Listening on: \(names.isEmpty ? "\(sourceCount) MIDI source(s)" : names.joined(separator: ", "))")
        print("Play the passage. Recording stops \(String(format: "%g", silenceSeconds)) s after your last note.")

        let start = Self.now()
        while true {
            Thread.sleep(forTimeInterval: 0.05)
            lock.lock()
            let started = firstEvent != nil
            let last = lastEvent
            let anyHeld = !held.isEmpty
            lock.unlock()
            let now = Self.now()
            if started && !anyHeld && now - last >= silenceSeconds { break }
            if now - start > maxSeconds { break }
        }

        lock.lock()
        defer { lock.unlock() }
        for (key, h) in held {
            notes.append(NoteEvent(pitch: key & 0x7F, onset: h.onset, offset: lastEvent, velocity: h.velocity, channel: key >> 7))
        }
        held.removeAll()
        let t0 = firstEvent ?? 0
        print("")
        return notes
            .map { n in
                var m = n
                m.onset -= t0
                m.offset -= t0
                m.onsetBeats = m.onset * 2 // the take is saved at 120 bpm
                return m
            }
            .sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
    }

    private func handle(_ list: UnsafePointer<MIDIEventList>) {
        // Universal MIDI Packet sizes in 32-bit words, indexed by message type (top 4 bits).
        let sizes = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
        for packetPointer in list.unsafeSequence() {
            let packet = packetPointer.pointee
            let time = Self.seconds(hostTime: packet.timeStamp == 0 ? mach_absolute_time() : packet.timeStamp)
            let count = Int(packet.wordCount)
            let words: [UInt32] = withUnsafeBytes(of: packet.words) { raw in
                Array(raw.bindMemory(to: UInt32.self).prefix(count))
            }
            var i = 0
            while i < words.count {
                let w = words[i]
                let type = Int(w >> 28)
                if type == 2 { // MIDI 1.0 channel voice message
                    let status = Int((w >> 16) & 0xF0)
                    let channel = Int((w >> 16) & 0x0F)
                    let data1 = Int((w >> 8) & 0x7F)
                    let data2 = Int(w & 0x7F)
                    if status == 0x90 && data2 > 0 {
                        noteOn(channel: channel, pitch: data1, velocity: data2, at: time)
                    } else if status == 0x80 || (status == 0x90 && data2 == 0) {
                        noteOff(channel: channel, pitch: data1, at: time)
                    }
                }
                i += sizes[type]
            }
        }
    }

    private func noteOn(channel: Int, pitch: Int, velocity: Int, at time: Double) {
        lock.lock()
        defer { lock.unlock() }
        let key = channel << 7 | pitch
        if let h = held[key] { // re-struck without a release
            notes.append(NoteEvent(pitch: pitch, onset: h.onset, offset: time, velocity: h.velocity, channel: channel))
        }
        held[key] = (time, velocity)
        if firstEvent == nil { firstEvent = time }
        lastEvent = time
        print(PitchName.of(pitch), terminator: " ")
        fflush(stdout)
    }

    private func noteOff(channel: Int, pitch: Int, at time: Double) {
        lock.lock()
        defer { lock.unlock() }
        let key = channel << 7 | pitch
        guard let h = held.removeValue(forKey: key) else { return }
        notes.append(NoteEvent(pitch: pitch, onset: h.onset, offset: time, velocity: h.velocity, channel: channel))
        lastEvent = max(lastEvent, time)
    }

    private static func seconds(hostTime: UInt64) -> Double {
        Double(hostTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    private static func now() -> Double { seconds(hostTime: mach_absolute_time()) }
}
#endif
