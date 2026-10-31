import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A message for chat completions: text and images (PNG or JPEG).
public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public enum Part: Sendable, Equatable {
        case text(String)
        case image(Data, mimeType: String)
    }

    public var role: Role
    public var parts: [Part]

    public init(_ role: Role, _ parts: [Part]) { self.role = role; self.parts = parts }
    public static func system(_ text: String) -> ChatMessage { .init(.system, [.text(text)]) }
    public static func user(_ text: String) -> ChatMessage { .init(.user, [.text(text)]) }
    public static func user(_ parts: [Part]) -> ChatMessage { .init(.user, parts) }

    var json: JSONValue {
        // Plain text stays a string, the most widely accepted shape.
        if parts.count == 1, case .text(let t) = parts[0] { return ["role": .string(role.rawValue), "content": .string(t)] }
        let content: [JSONValue] = parts.map {
            switch $0 {
            case .text(let t): return ["type": "text", "text": .string(t)]
            case .image(let data, let mime):
                return ["type": "image_url", "image_url": ["url": .string("data:\(mime);base64,\(data.base64EncodedString())")]]
            }
        }
        return ["role": .string(role.rawValue), "content": .array(content)]
    }
}

public struct ChatOptions: Sendable {
    public var model: String
    /// A JSON schema the reply must match (decoding is constrained server-side).
    public var schema: (name: String, schema: JSONValue)?
    /// "minimal", "low", "medium", "high" … on Muse Spark. Nil leaves the server default.
    public var reasoningEffort: String?
    public var maxTokens: Int?
    public var temperature: Double?
    /// Stream the reply. Needed for long reasoning (reading music): a non-streamed request
    /// that takes too long to start answering fails with HTTP 504.
    public var stream: Bool

    public init(model: String = MetaModels.spark, schema: (name: String, schema: JSONValue)? = nil,
                reasoningEffort: String? = nil, maxTokens: Int? = nil, temperature: Double? = nil,
                stream: Bool = false) {
        self.model = model
        self.schema = schema
        self.reasoningEffort = reasoningEffort
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.stream = stream
    }
}

public struct ChatResult: Sendable {
    public var text: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var seconds: Double

    /// The reply decoded as JSON into `T` (use with `ChatOptions.schema`).
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
        catch { throw ModelError.badResponse("reply isn't valid \(T.self) JSON: \(text.prefix(200))") }
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var sessionID: String?
    public var audioMilliseconds: Int?
}

/// Talks to Meta Model API, or any OpenAI-compatible endpoint (Fireworks, Modal) for chat.
/// Every call is recorded in `UsageLog`.
public struct ModelClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let endpoint: ModelEndpoint
    let transport: Transport
    let log: UsageLog

    public init(endpoint: ModelEndpoint, log: UsageLog = .shared, transport: Transport? = nil) {
        self.endpoint = endpoint
        self.log = log
        self.transport = transport ?? ModelClient.urlSession()
    }

    /// The configured client for a provider (Keychain key, saved Modal URL).
    public static func configured(_ provider: ModelProvider = .meta) throws -> ModelClient {
        ModelClient(endpoint: try .configured(provider))
    }

    public static func urlSession(_ session: URLSession = .shared) -> Transport {
        { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ModelError.badResponse("not HTTP") }
            return (data, http)
        }
    }

    // MARK: Chat

    public func chat(_ messages: [ChatMessage], options: ChatOptions = .init()) async throws -> ChatResult {
        var body: [String: JSONValue] = ["model": .string(options.model), "messages": .array(messages.map(\.json))]
        if let s = options.schema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": .string(s.name), "schema": s.schema]]
        }
        if let e = options.reasoningEffort { body["reasoning_effort"] = .string(e) }
        if let m = options.maxTokens { body["max_tokens"] = .number(Double(m)) }
        if let t = options.temperature { body["temperature"] = .number(t) }
        if options.stream {
            body["stream"] = true
            body["stream_options"] = ["include_usage": true]
        }

        let started = Date()
        do {
            var req = try request("chat/completions", json: .object(body))
            if options.stream { req.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
            let (data, _) = try await send(req)
            let parsed = options.stream ? try Self.parseChatStream(data) : try Self.parseChat(data)
            let result = ChatResult(
                text: parsed.text, model: parsed.model ?? options.model,
                inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                seconds: Date().timeIntervalSince(started))
            await record(options.model, "chat", started, input: result.inputTokens, output: result.outputTokens)
            return result
        } catch {
            await record(options.model, "chat", started, error: error)
            throw error
        }
    }

    struct ParsedChat {
        var text: String
        var model: String?
        var inputTokens: Int?
        var outputTokens: Int?
    }

    static func parseChat(_ data: Data) throws -> ParsedChat {
        let json = try JSONValue(parsing: data)
        guard let text = json["choices"]?[0]?["message"]?["content"]?.stringValue else {
            throw ModelError.badResponse("no choices[0].message.content")
        }
        return ParsedChat(text: text, model: json["model"]?.stringValue,
                          inputTokens: json["usage"]?["prompt_tokens"]?.intValue,
                          outputTokens: json["usage"]?["completion_tokens"]?.intValue)
    }

    /// A streamed chat completion: the content deltas joined, and the usage from the last chunk.
    static func parseChatStream(_ data: Data) throws -> ParsedChat {
        var out = ParsedChat(text: "")
        for payload in ServerSentEvents.dataPayloads(data) {
            guard let event = try? JSONValue(parsing: Data(payload.utf8)) else { continue }
            if let error = event["error"] {
                throw ModelError.streamError(error["message"]?.stringValue ?? "unknown")
            }
            if out.model == nil { out.model = event["model"]?.stringValue }
            for choice in event["choices"]?.arrayValue ?? [] {
                if let piece = choice["delta"]?["content"]?.stringValue { out.text += piece }
            }
            if let usage = event["usage"], usage != .null {
                out.inputTokens = usage["prompt_tokens"]?.intValue ?? out.inputTokens
                out.outputTokens = usage["completion_tokens"]?.intValue ?? out.outputTokens
            }
        }
        guard !out.text.isEmpty else { throw ModelError.badResponse("stream had no content") }
        return out
    }

    // MARK: Segmentation (SAM 3.1)

    /// Every match for a short noun phrase ("music staff") in a PNG or JPEG image.
    public func segment(image: Data, mimeType: String = "image/png", prompt: String,
                        model: String = MetaModels.sam) async throws -> [Segment] {
        let body: JSONValue = [
            "model": .string(model),
            "stream": true,
            "input": [[
                "type": "message", "role": "user",
                "content": [
                    ["type": "input_text", "text": .string(prompt)],
                    ["type": "input_image", "image_url": .string("data:\(mimeType);base64,\(image.base64EncodedString())")],
                ],
            ]],
        ]
        let started = Date()
        do {
            var req = try request("responses", json: body)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let (data, _) = try await send(req)
            let (text, usage) = try Self.collectOutputText(fromEventStream: data)
            await record(model, "segment", started, input: usage.input, output: usage.output)
            return SegmentationOutput.parse(text)
        } catch {
            await record(model, "segment", started, error: error)
            throw error
        }
    }

    /// The `output_text` lane of a Responses event stream: each delta is one line (one frame).
    static func collectOutputText(fromEventStream data: Data) throws -> (String, (input: Int?, output: Int?)) {
        var lines: [String] = []
        var usage: (input: Int?, output: Int?) = (nil, nil)
        for payload in ServerSentEvents.dataPayloads(data) {
            guard let event = try? JSONValue(parsing: Data(payload.utf8)) else { continue }
            switch event["type"]?.stringValue {
            case "response.output_text.delta":
                if let d = event["delta"]?.stringValue { lines.append(d) }
            case "response.completed":
                let u = event["response"]?["usage"]
                usage = (u?["input_tokens"]?.intValue, u?["output_tokens"]?.intValue)
            case "error", "response.failed":
                let message = event["error"]?["message"]?.stringValue
                    ?? event["response"]?["error"]?["message"]?.stringValue
                    ?? event["message"]?.stringValue ?? "unknown"
                throw ModelError.streamError(message)
            default:
                break
            }
        }
        return (lines.joined(separator: "\n"), usage)
    }

    // MARK: Transcription (Muse Voice Transcribe)

    /// One push-to-talk recording: mono 16-bit WAV at 16 or 24 kHz (see `WAV.encode`).
    public func transcribe(wav: Data, model: String = MetaModels.transcribe,
                           languages: [String] = ["English"], keywords: [String] = []) async throws -> Transcript {
        var settings: [String: JSONValue] = [
            "model": .string(model), "audioEncoding": "WAV", "mode": "PUSH_TO_TALK",
            "languageBias": .array(languages.map(JSONValue.string)),
        ]
        if !keywords.isEmpty { settings["keywords"] = .array(keywords.map(JSONValue.string)) }

        var form = MultipartForm()
        form.add(name: "request", contentType: "application/json", data: try JSONValue.object(settings).data())
        form.add(name: "audio", filename: "audio.wav", contentType: "audio/wav", data: wav)

        var req = try request("asr/transcribe")
        req.httpMethod = "POST"
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = form.finished()

        let started = Date()
        do {
            let (data, _) = try await send(req)
            let json = try JSONValue(parsing: data)
            let transcript = Transcript(
                text: json["transcript"]?.stringValue ?? "",
                sessionID: json["sessionId"]?.stringValue,
                audioMilliseconds: json["audioDurationMs"]?.intValue)
            await record(model, "transcribe", started, audio: transcript.audioMilliseconds.map { Double($0) / 1000 })
            return transcript
        } catch {
            await record(model, "transcribe", started, error: error)
            throw error
        }
    }

    // MARK: Models

    public func listModels() async throws -> [String] {
        var req = try request("models")
        req.httpMethod = "GET"
        let started = Date()
        do {
            let (data, _) = try await send(req)
            let ids = (try JSONValue(parsing: data))["data"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
            await record("-", "models", started)
            return ids
        } catch {
            await record("-", "models", started, error: error)
            throw error
        }
    }

    // MARK: Plumbing

    func request(_ path: String, json: JSONValue? = nil) throws -> URLRequest {
        var req = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        req.timeoutInterval = 300 // reasoning on a page of music can take a while
        if let key = endpoint.apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try json.data()
        }
        return req
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else { throw ModelError.fromHTTP(status: response.statusCode, body: data) }
        return (data, response)
    }

    private func record(_ model: String, _ op: String, _ started: Date, input: Int? = nil, output: Int? = nil,
                        audio: Double? = nil, error: Error? = nil) async {
        await log.record(.init(
            date: started, provider: endpoint.provider, model: model, operation: op,
            seconds: Date().timeIntervalSince(started), inputTokens: input, outputTokens: output,
            audioSeconds: audio, error: error.map { ($0 as? LocalizedError)?.errorDescription ?? "\($0)" }))
    }
}
