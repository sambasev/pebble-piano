import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// H1's connection checks: one small call per endpoint, each with an answer we can verify.
public enum AIChecks {
    public struct Result: Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var passed: Bool
        public var detail: String
        public var seconds: Double
    }

    /// Meta: models list, structured chat, vision, SAM 3.1 and transcription.
    /// Fireworks / Modal: models list, and a chat call when a model ID is set.
    public static func run(_ client: ModelClient, openModel: String? = nil) async -> [Result] {
        var results: [Result] = []
        results.append(await check("Models list") {
            let ids = try await client.listModels()
            if client.endpoint.provider == .meta {
                let wanted = [MetaModels.spark, MetaModels.sam, MetaModels.transcribe]
                let missing = wanted.filter { !ids.contains($0) }
                return (missing.isEmpty, missing.isEmpty ? "\(ids.count) models, including all three Pebble Piano uses"
                                                         : "missing: \(missing.joined(separator: ", "))")
            }
            return (!ids.isEmpty, "\(ids.count) models: \(ids.prefix(5).joined(separator: ", "))")
        })

        guard client.endpoint.provider == .meta else {
            if let model = openModel {
                results.append(await check("Chat (\(model))") {
                    let r = try await client.chat([.user("Reply with the single word: ready")],
                                                  options: .init(model: model, maxTokens: 20))
                    let ok = r.text.lowercased().contains("ready")
                    return (ok, "“\(r.text.prefix(60))”")
                })
            }
            return results
        }

        results.append(await check("Structured chat (\(MetaModels.spark))") {
            struct Reply: Decodable { let notes: [String] }
            let schema: JSONValue = [
                "type": "object", "additionalProperties": false, "required": ["notes"],
                "properties": ["notes": ["type": "array", "items": ["type": "string"]]],
            ]
            let r = try await client.chat(
                [.system("You are a piano teacher. Answer in JSON."),
                 .user("List the notes of a C major triad in root position, as note names without octaves.")],
                options: .init(schema: ("Triad", schema), reasoningEffort: "low"))
            let notes = try r.decode(Reply.self).notes.map { $0.uppercased() }
            return (notes == ["C", "E", "G"], "notes \(notes)")
        })

        #if canImport(CoreGraphics) && canImport(ImageIO)
        let png = TestImage.blocksPNG(count: 3)
        results.append(await check("Vision (\(MetaModels.spark))") {
            struct Reply: Decodable { let count: Int }
            let schema: JSONValue = [
                "type": "object", "additionalProperties": false, "required": ["count"],
                "properties": ["count": ["type": "integer"]],
            ]
            let r = try await client.chat(
                [.user([.text("How many black rectangles are in this image?"), .image(png, mimeType: "image/png")])],
                options: .init(schema: ("Count", schema), reasoningEffort: "low"))
            let count = try r.decode(Reply.self).count
            return (count == 3, "counted \(count) of 3")
        })

        results.append(await check("Segmentation (\(MetaModels.sam))") {
            let segments = try await client.segment(image: png, prompt: "black rectangle")
            let boxes = segments.map { "(\($0.box.x1),\($0.box.y1))–(\($0.box.x2),\($0.box.y2))" }
            return (segments.count == 3, "found \(segments.count) of 3: \(boxes.joined(separator: " "))")
        })
        #endif

        results.append(await check("Transcription (\(MetaModels.transcribe))") {
            // One second of silence: checks the endpoint and the WAV format, not recognition.
            let wav = WAV.encode(samples: [Int16](repeating: 0, count: WAV.transcribeRate), sampleRate: WAV.transcribeRate)
            let t = try await client.transcribe(wav: wav)
            return (true, "accepted; transcript “\(t.text)”")
        })
        return results
    }

    static func check(_ name: String, _ body: () async throws -> (Bool, String)) async -> Result {
        let started = Date()
        do {
            let (ok, detail) = try await body()
            return Result(name: name, passed: ok, detail: detail, seconds: Date().timeIntervalSince(started))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return Result(name: name, passed: false, detail: message, seconds: Date().timeIntervalSince(started))
        }
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO)
/// Images for checks, drawn in code so they need no files.
public enum TestImage {
    /// Black rectangles spaced along a white strip, like staves down a page.
    public static func blocksPNG(count: Int, width: Int = 480, height: Int = 360) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let band = Double(height) / Double(count)
        for i in 0..<count {
            ctx.fill(CGRect(x: 40, y: Double(i) * band + band * 0.25, width: Double(width - 80), height: band * 0.5))
        }
        guard let image = ctx.makeImage() else { return Data() }
        return png(image)
    }

    public static func png(_ image: CGImage) -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
#endif
