import Foundation

/// Server-sent events: the `data:` payloads of a complete event-stream body, in order.
enum ServerSentEvents {
    static func dataPayloads(_ body: Data) -> [String] {
        let text = String(decoding: body, as: UTF8.self)
        var payloads: [String] = []
        var current: [String] = []
        // An event ends at a blank line; its data lines join with newlines.
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            if line.isEmpty {
                if !current.isEmpty { payloads.append(current.joined(separator: "\n")); current = [] }
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                current.append(String(value))
            }
        }
        if !current.isEmpty { payloads.append(current.joined(separator: "\n")) }
        return payloads.filter { $0 != "[DONE]" }
    }
}

/// A `multipart/form-data` body.
struct MultipartForm {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String = "PianoAI-\(UUID().uuidString)") { self.boundary = boundary }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(name: String, filename: String? = nil, contentType: String, data: Data) {
        var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
        if let filename { header += "; filename=\"\(filename)\"" }
        header += "\r\nContent-Type: \(contentType)\r\n\r\n"
        body.append(Data(header.utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finished() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }
}

/// Mono 16-bit PCM WAV, the format Muse Voice Transcribe accepts (16 kHz or 24 kHz).
public enum WAV {
    public static let transcribeRate = 24_000

    public static func encode(samples: [Int16], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(Data("RIFF".utf8)); u32(36 + dataBytes); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(dataBytes)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }

    /// Float samples (−1…1) at any rate, resampled linearly to `targetRate`. Good enough for
    /// speech; not for music.
    public static func encode(floats: [Float], sampleRate: Double, targetRate: Int = transcribeRate) -> Data {
        guard !floats.isEmpty, sampleRate > 0 else { return encode(samples: [], sampleRate: targetRate) }
        let ratio = sampleRate / Double(targetRate)
        let count = Int(Double(floats.count) / ratio)
        var out = [Int16](); out.reserveCapacity(count)
        for i in 0..<count {
            let pos = Double(i) * ratio
            let j = Int(pos)
            let frac = Float(pos - Double(j))
            let a = floats[min(j, floats.count - 1)], b = floats[min(j + 1, floats.count - 1)]
            let v = max(-1, min(1, a + (b - a) * frac))
            out.append(Int16(v * Float(Int16.max)))
        }
        return encode(samples: out, sampleRate: targetRate)
    }
}
