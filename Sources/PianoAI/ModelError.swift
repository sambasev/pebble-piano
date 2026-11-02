import Foundation

public enum ModelError: Error, Equatable, LocalizedError {
    case missingKey(ModelProvider)
    case missingBaseURL(ModelProvider)
    /// The server answered with an error status. `message` is the server's own message.
    case http(status: Int, message: String)
    /// The response arrived but wasn't in the expected shape.
    case badResponse(String)
    /// A streamed response ended with an error event.
    case streamError(String)
    /// The call ran past its `ChatOptions.deadline` and was cancelled.
    case timedOut(seconds: TimeInterval)
    case keychain(Int32)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let p): return "No \(p.displayName) key. Add one in AI settings (or set \(p.keyEnvironmentVariable))."
        case .missingBaseURL(let p): return "No base URL for \(p.displayName). Add your deployment's URL in AI settings."
        case .http(let status, let message): return "HTTP \(status): \(message)"
        case .badResponse(let what): return "Unexpected response: \(what)"
        case .streamError(let message): return "Stream error: \(message)"
        case .timedOut(let seconds):
            return seconds >= 120 ? "no answer after \(Int(seconds / 60)) minutes" : "no answer after \(Int(seconds)) seconds"
        case .keychain(let status): return "Keychain error \(status)"
        }
    }

    /// Pulls the message out of an OpenAI-style error body, or falls back to the raw text.
    static func fromHTTP(status: Int, body: Data) -> ModelError {
        if let json = try? JSONValue(parsing: body),
           let message = json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue {
            return .http(status: status, message: message)
        }
        let text = String(decoding: body.prefix(500), as: UTF8.self)
        return .http(status: status, message: text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : text)
    }
}
