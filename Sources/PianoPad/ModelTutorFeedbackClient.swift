#if os(macOS)
import PianoAI
import PianoLessons

/// Keeps the deterministic tutor independent of the hackathon's shared AI transport.
struct ModelTutorFeedbackClient: TutorFeedbackClient {
    let client: ModelClient
    let model: String

    static func configured() throws -> Self {
        Self(client: try ModelClient.configured(.meta), model: AISettings.shared.tutorModel)
    }

    func explain(context: String, question: String) async throws -> String {
        let reply = try await client.chat([
            .system(TutorFeedbackInstructions.teacher),
            .user(context + "\nQuestion: " + question)
        ], options: .init(model: model, reasoningEffort: "low", maxTokens: 2048, requestTimeout: 20))
        let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ModelError.badResponse("empty tutor explanation") }
        return text
    }
}
#endif
