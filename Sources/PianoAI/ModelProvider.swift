import Foundation

/// Where a model runs. Meta Model API hosts Muse Spark, SAM 3.1 and Muse Voice Transcribe.
/// Fireworks and Modal host open-weight models behind OpenAI-compatible endpoints.
public enum ModelProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case meta
    case fireworks
    case modal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meta: return "Meta Model API"
        case .fireworks: return "Fireworks"
        case .modal: return "Modal"
        }
    }

    /// The fixed base URL, or nil for Modal, whose URL is your own deployment.
    public var defaultBaseURL: URL? {
        switch self {
        case .meta: return URL(string: "https://api.meta.ai/v1")
        case .fireworks: return URL(string: "https://api.fireworks.ai/inference/v1")
        case .modal: return nil
        }
    }

    /// Read when no key is saved in the Keychain, so `swift test` and the command line work.
    public var keyEnvironmentVariable: String {
        switch self {
        case .meta: return "MODEL_API_KEY"
        case .fireworks: return "FIREWORKS_API_KEY"
        case .modal: return "MODAL_API_KEY"
        }
    }

    /// Modal deployments (vLLM with `--api-key`) may run without a key.
    public var requiresKey: Bool { self != .modal }
}

/// Meta's model IDs, in one place so a version bump is one line.
public enum MetaModels {
    /// Reading sheet music, planning lessons and the tutor.
    public static let spark = "muse-spark-1.3"
    /// Finding systems and bars on a page.
    public static let sam = "sam-3.1"
    /// Voice questions.
    public static let transcribe = "muse-voice-transcribe-1.0"
}

/// A provider with its resolved base URL and key.
public struct ModelEndpoint: Sendable, Equatable {
    public var provider: ModelProvider
    public var baseURL: URL
    public var apiKey: String?

    public init(provider: ModelProvider, baseURL: URL, apiKey: String?) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// The endpoint from saved settings: the Keychain (or environment) key, and for Modal
    /// the saved base URL. Throws when something required is missing.
    public static func configured(_ provider: ModelProvider, settings: AISettings = .shared) throws -> ModelEndpoint {
        guard let base = provider.defaultBaseURL ?? settings.modalBaseURL else { throw ModelError.missingBaseURL(provider) }
        let key = APIKeyStore.key(for: provider)
        if provider.requiresKey, key == nil { throw ModelError.missingKey(provider) }
        return ModelEndpoint(provider: provider, baseURL: base, apiKey: key)
    }
}

/// Non-secret AI settings, kept in UserDefaults.
public final class AISettings: @unchecked Sendable {
    public static let shared = AISettings()

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Your Modal deployment's OpenAI-compatible base URL, ending in `/v1`.
    public var modalBaseURL: URL? {
        get { defaults.string(forKey: "ai.modal.baseURL").flatMap { URL(string: $0) } }
        set { defaults.set(newValue?.absoluteString, forKey: "ai.modal.baseURL") }
    }

    /// The model ID to check on an open-weight provider (Fireworks or Modal).
    public func openModel(for provider: ModelProvider) -> String? {
        let value = defaults.string(forKey: "ai.\(provider.rawValue).model")?.trimmingCharacters(in: .whitespaces)
        return (value?.isEmpty ?? true) ? nil : value
    }

    public func setOpenModel(_ model: String?, for provider: ModelProvider) {
        defaults.set(model, forKey: "ai.\(provider.rawValue).model")
    }
}
