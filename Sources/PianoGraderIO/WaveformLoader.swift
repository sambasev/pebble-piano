#if canImport(AVFoundation)
import AVFoundation
import Foundation
import PianoGraderCore

/// Reads an audio file on a background queue and summarises it for drawing.
public enum WaveformLoader {
    public struct Loaded: Sendable {
        public var peaks: WaveformPeaks
        /// Length of the file in seconds.
        public var duration: Double
        public var sampleRate: Double
        public var channels: Int
    }

    /// Calls `completion` on the main queue. `progress` (0–1) is also reported on the main queue.
    public static func load(_ url: URL, bucketsPerSecond: Double = 400,
                            progress: ((Double) -> Void)? = nil,
                            completion: @escaping (Result<Loaded, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try read(url, bucketsPerSecond: bucketsPerSecond, progress: progress) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Mixes all channels to mono and builds peaks. Runs on the calling thread.
    public static func read(_ url: URL, bucketsPerSecond: Double = 400,
                            progress: ((Double) -> Void)? = nil) throws -> Loaded {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw NSError(domain: "WaveformLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't allocate an audio buffer."])
        }
        var builder = WaveformBuilder(sampleRate: format.sampleRate, bucketsPerSecond: bucketsPerSecond)
        var mono = [Float](repeating: 0, count: Int(chunk))
        let total = max(1, file.length)
        var lastReported = -1.0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            let scale = 1 / Float(max(1, channels))
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += data[c][i] }
                mono[i] = sum * scale
            }
            mono.withUnsafeBufferPointer { builder.append(UnsafeBufferPointer(rebasing: $0[0..<n])) }
            if let progress {
                let done = Double(file.framePosition) / Double(total)
                if done - lastReported > 0.05 {
                    lastReported = done
                    DispatchQueue.main.async { progress(done) }
                }
            }
        }
        return Loaded(peaks: builder.finish(), duration: Double(file.length) / format.sampleRate,
                      sampleRate: format.sampleRate, channels: channels)
    }
}
#endif
