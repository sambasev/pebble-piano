#if os(macOS)
import Foundation
import PianoAI
import PianoLessons

/// Asks Muse Spark (the tutor model) for a lesson plan, constrained to the plan's JSON schema.
struct ModelLessonPlanModel: LessonPlanModel {
    let client: ModelClient
    let model: String

    static func configured() throws -> Self {
        Self(client: try ModelClient.configured(.meta), model: AISettings.shared.tutorModel)
    }

    func propose(system: String, user: String, schemaName: String, schema: String) async throws -> String {
        let reply = try await client.chat([.system(system), .user(user)],
                                          options: .init(model: model, schema: (name: schemaName, schema: try JSONValue(parsing: Data(schema.utf8))),
                                                         reasoningEffort: "low", maxTokens: 4096, requestTimeout: 30))
        return reply.text
    }
}
#endif
