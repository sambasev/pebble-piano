import Foundation

public enum MIDIFileError: Error, CustomStringConvertible {
    case notAMIDIFile
    case unsupportedTimeDivision
    case truncated(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .notAMIDIFile: return "Not a Standard MIDI File (missing MThd header)."
        case .unsupportedTimeDivision: return "SMPTE time division is not supported; export with ticks per quarter note."
        case .truncated(let what): return "MIDI file ended early while reading \(what)."
        case .malformed(let what): return "Malformed MIDI file: \(what)."
        }
    }
}

/// Minimal Standard MIDI File reader and writer: formats 0 and 1, note on/off,
/// tempo, time-signature, key-signature and track-name meta events. Everything else is skipped.
public enum MIDIFile {

    // MARK: Reading

    public static func read(url: URL) throws -> MIDISequence {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> MIDISequence {
        var r = ByteReader(bytes: [UInt8](data))
        guard try r.readASCII(4) == "MThd" else { throw MIDIFileError.notAMIDIFile }
        let headerLength = Int(try r.readUInt32())
        _ = try r.readUInt16() // format: 0 and 1 are handled the same way (tracks are merged)
        let trackCount = Int(try r.readUInt16())
        let division = try r.readUInt16()
        guard division & 0x8000 == 0 else { throw MIDIFileError.unsupportedTimeDivision }
        let ppq = max(1, Int(division))
        try r.skip(headerLength - 6)

        var events: [RawEvent] = []
        var order = 0 // keeps file order stable when sorting
        var title: String? = nil

        for trackIndex in 0..<trackCount {
            // Skip any non-track chunks.
            var chunkID = try r.readASCII(4)
            var chunkLength = Int(try r.readUInt32())
            while chunkID != "MTrk" {
                try r.skip(chunkLength)
                chunkID = try r.readASCII(4)
                chunkLength = Int(try r.readUInt32())
            }
            let end = r.position + chunkLength
            guard end <= r.count else { throw MIDIFileError.truncated("track chunk") }

            var tick = 0
            var runningStatus: UInt8? = nil
            trackLoop: while r.position < end {
                tick += try r.readVLQ()
                var status = try r.peek()
                if status & 0x80 != 0 {
                    _ = try r.readByte()
                } else {
                    guard let rs = runningStatus else { throw MIDIFileError.malformed("data byte without a status byte") }
                    status = rs
                }

                switch status {
                case 0xFF:
                    runningStatus = nil
                    let type = try r.readByte()
                    let length = try r.readVLQ()
                    let payload = try r.readBytes(length)
                    if type == 0x51, payload.count == 3 {
                        let usPerQuarter = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                        events.append(RawEvent(tick: tick, order: order, kind: .tempo(usPerQuarter: max(1, usPerQuarter))))
                    } else if type == 0x58, payload.count >= 2 {
                        let ts = TimeSignature(numerator: Int(payload[0]), denominator: 1 << Int(payload[1]))
                        events.append(RawEvent(tick: tick, order: order, kind: .timeSignature(ts)))
                    } else if type == 0x59, payload.count >= 2 {
                        let key = KeySignature(fifths: Int(Int8(bitPattern: payload[0])), isMinor: payload[1] == 1)
                        events.append(RawEvent(tick: tick, order: order, kind: .keySignature(key)))
                    } else if type == 0x03, trackIndex == 0, title == nil {
                        let name = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { title = name }
                    } else if type == 0x2F {
                        break trackLoop
                    }
                case 0xF0, 0xF7:
                    runningStatus = nil
                    let length = try r.readVLQ()
                    try r.skip(length)
                default:
                    runningStatus = status
                    let kind = status & 0xF0
                    let channel = Int(status & 0x0F)
                    let d1 = try r.readByte()
                    var d2: UInt8 = 0
                    if kind != 0xC0 && kind != 0xD0 { d2 = try r.readByte() }
                    if kind == 0x90 && d2 > 0 {
                        events.append(RawEvent(tick: tick, order: order, kind: .noteOn(channel: channel, pitch: Int(d1), velocity: Int(d2), track: trackIndex)))
                    } else if kind == 0x80 || (kind == 0x90 && d2 == 0) {
                        events.append(RawEvent(tick: tick, order: order, kind: .noteOff(channel: channel, pitch: Int(d1))))
                    }
                }
                order += 1
            }
            r.position = end
        }

        // Merge tracks. At equal ticks: meta first, then note-offs, then note-ons,
        // so a repeated note's release is processed before its next attack.
        events.sort { a, b in
            if a.tick != b.tick { return a.tick < b.tick }
            if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
            return a.order < b.order
        }

        // Tempo map: tick → seconds.
        var tempoMap = TempoMap(ppq: ppq)
        var timeSignature: TimeSignature? = nil
        var keySignature: KeySignature? = nil
        for e in events {
            switch e.kind {
            case .tempo(let us): tempoMap.add(tick: e.tick, usPerQuarter: us)
            case .timeSignature(let ts): if timeSignature == nil { timeSignature = ts }
            case .keySignature(let key): if keySignature == nil { keySignature = key }
            default: break
            }
        }

        // Pair note-ons with note-offs (first in, first out per channel and pitch).
        var pending: [Int: [(tick: Int, velocity: Int, track: Int)]] = [:]
        var notes: [NoteEvent] = []
        var lastTick = 0
        func emit(_ key: Int, onTick: Int, velocity: Int, track: Int, offTick: Int) {
            let off = max(offTick, onTick)
            notes.append(NoteEvent(
                pitch: key & 0x7F,
                onset: tempoMap.seconds(atTick: onTick),
                offset: tempoMap.seconds(atTick: off),
                velocity: velocity,
                onsetBeats: Double(onTick) / Double(ppq),
                offsetBeats: Double(off) / Double(ppq),
                channel: key >> 7,
                track: track
            ))
        }
        for e in events {
            lastTick = max(lastTick, e.tick)
            switch e.kind {
            case .noteOn(let ch, let pitch, let vel, let track):
                pending[ch << 7 | pitch, default: []].append((e.tick, vel, track))
            case .noteOff(let ch, let pitch):
                let key = ch << 7 | pitch
                if var stack = pending[key], !stack.isEmpty {
                    let on = stack.removeFirst()
                    pending[key] = stack
                    emit(key, onTick: on.tick, velocity: on.velocity, track: on.track, offTick: e.tick)
                }
            default: break
            }
        }
        for (key, stack) in pending {
            for on in stack { emit(key, onTick: on.tick, velocity: on.velocity, track: on.track, offTick: lastTick) }
        }

        return MIDISequence(
            notes: notes,
            ticksPerQuarter: ppq,
            initialTempoBPM: tempoMap.initialBPM,
            timeSignature: timeSignature ?? .common,
            keySignature: keySignature,
            title: title
        )
    }

    // MARK: Writing

    /// Writes notes at a fixed tempo (default 120 bpm, 480 ticks per quarter). Used to save
    /// live takes; onsets in seconds are converted to ticks at that tempo. Notes from one
    /// track give a format-0 file; notes from several tracks give format 1, one track each.
    public static func write(notes: [NoteEvent], tempoBPM: Double = 120, ticksPerQuarter: Int = 480,
                             timeSignature: TimeSignature = .common, keySignature: KeySignature? = nil) -> Data {
        let ticksPerSecond = Double(ticksPerQuarter) * tempoBPM / 60.0
        struct Out { let tick: Int; let rank: Int; let bytes: [UInt8] }
        let trackIndices = Array(Set(notes.map(\.track))).sorted()
        let tracks = trackIndices.isEmpty ? [0] : trackIndices

        var chunks: [[UInt8]] = []
        for (position, trackIndex) in tracks.enumerated() {
            var out: [Out] = []
            for n in notes where n.track == trackIndex {
                let on = max(0, Int((n.onset * ticksPerSecond).rounded()))
                let off = max(on + 1, Int((n.offset * ticksPerSecond).rounded()))
                let ch = UInt8(max(0, min(15, n.channel)))
                let pitch = UInt8(max(0, min(127, n.pitch)))
                let vel = UInt8(max(1, min(127, n.velocity)))
                out.append(Out(tick: on, rank: 1, bytes: [0x90 | ch, pitch, vel]))
                out.append(Out(tick: off, rank: 0, bytes: [0x80 | ch, pitch, 0]))
            }
            out.sort { ($0.tick, $0.rank) < ($1.tick, $1.rank) }

            var track: [UInt8] = []
            if position == 0 {
                let us = Int((60_000_000.0 / tempoBPM).rounded())
                track += [0x00, 0xFF, 0x51, 0x03, UInt8((us >> 16) & 0xFF), UInt8((us >> 8) & 0xFF), UInt8(us & 0xFF)]
                let denomPower = UInt8(max(0, Int(log2(Double(timeSignature.denominator)).rounded())))
                track += [0x00, 0xFF, 0x58, 0x04, UInt8(timeSignature.numerator), denomPower, 24, 8]
                if let key = keySignature {
                    track += [0x00, 0xFF, 0x59, 0x02, UInt8(bitPattern: Int8(key.fifths)), key.isMinor ? 1 : 0]
                }
            }
            var lastTick = 0
            for e in out {
                track += vlq(e.tick - lastTick)
                track += e.bytes
                lastTick = e.tick
            }
            track += [0x00, 0xFF, 0x2F, 0x00]
            chunks.append(track)
        }

        var data: [UInt8] = Array("MThd".utf8)
        data += be32(6) + be16(chunks.count > 1 ? 1 : 0) + be16(chunks.count) + be16(ticksPerQuarter)
        for track in chunks {
            data += Array("MTrk".utf8) + be32(track.count) + track
        }
        return Data(data)
    }

    // MARK: Helpers

    static func vlq(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8(v & 0x7F) | 0x80, at: 0)
            v >>= 7
        }
        return bytes
    }

    private static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func be16(_ v: Int) -> [UInt8] {
        [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}

// MARK: - Internals

private struct RawEvent {
    enum Kind {
        case noteOn(channel: Int, pitch: Int, velocity: Int, track: Int)
        case noteOff(channel: Int, pitch: Int)
        case tempo(usPerQuarter: Int)
        case timeSignature(TimeSignature)
        case keySignature(KeySignature)

        var rank: Int {
            switch self {
            case .tempo, .timeSignature, .keySignature: return 0
            case .noteOff: return 1
            case .noteOn: return 2
            }
        }
    }
    let tick: Int
    let order: Int
    let kind: Kind
}

private struct TempoMap {
    struct Segment { let tick: Int; let seconds: Double; let usPerQuarter: Int }
    let ppq: Int
    private(set) var segments: [Segment]

    init(ppq: Int) {
        self.ppq = ppq
        self.segments = [Segment(tick: 0, seconds: 0, usPerQuarter: 500_000)]
    }

    var initialBPM: Double { 60_000_000.0 / Double(segments[0].usPerQuarter) }

    /// Tempo events must be added in tick order.
    mutating func add(tick: Int, usPerQuarter: Int) {
        if tick == 0 || tick <= segments[segments.count - 1].tick {
            let last = segments.removeLast()
            segments.append(Segment(tick: last.tick, seconds: last.seconds, usPerQuarter: usPerQuarter))
            return
        }
        let start = seconds(atTick: tick)
        segments.append(Segment(tick: tick, seconds: start, usPerQuarter: usPerQuarter))
    }

    func seconds(atTick tick: Int) -> Double {
        var seg = segments[0]
        for s in segments where s.tick <= tick { seg = s }
        return seg.seconds + Double(tick - seg.tick) * Double(seg.usPerQuarter) / 1_000_000.0 / Double(ppq)
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var position = 0
    var count: Int { bytes.count }

    init(bytes: [UInt8]) { self.bytes = bytes }

    func peek() throws -> UInt8 {
        guard position < bytes.count else { throw MIDIFileError.truncated("event") }
        return bytes[position]
    }

    mutating func readByte() throws -> UInt8 {
        let b = try peek()
        position += 1
        return b
    }

    mutating func readBytes(_ n: Int) throws -> [UInt8] {
        guard n >= 0, position + n <= bytes.count else { throw MIDIFileError.truncated("\(n) bytes") }
        defer { position += n }
        return Array(bytes[position..<position + n])
    }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, position + n <= bytes.count else { throw MIDIFileError.truncated("chunk") }
        position += n
    }

    mutating func readASCII(_ n: Int) throws -> String {
        let bytes = try readBytes(n)
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    /// Variable-length quantity, at most 4 bytes.
    mutating func readVLQ() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let b = try readByte()
            value = (value << 7) | Int(b & 0x7F)
            if b & 0x80 == 0 { return value }
        }
        throw MIDIFileError.malformed("variable-length value longer than 4 bytes")
    }
}
