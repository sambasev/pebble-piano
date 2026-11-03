#if os(macOS)
import Foundation
import PianoAI
import PianoLessons

/// Ask your tutor, answered by Muse Spark (the tutor model), its reply constrained to
/// `{on_topic, reply}`. A reply that can't be read counts as off topic: the chat refuses
/// rather than show text that wasn't checked.
struct ModelTutorChatClient: TutorChatClient {
    let client: ModelClient
    let model: String

    static func configured() throws -> Self {
        Self(client: try ModelClient.configured(.meta), model: AISettings.shared.tutorModel)
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "on_topic": ["type": "boolean"],
            "reply": ["type": "string"],
            "action": ["anyOf": [
                ["type": "null"],
                ["type": "object", "properties": [
                    "kind": ["type": "string", "enum": .array(TutorChatAction.Kind.allCases.map { .string($0.rawValue) })],
                    "fromBar": ["type": ["integer", "null"]], "toBar": ["type": ["integer", "null"]],
                    "hand": ["type": ["string", "null"], "enum": ["R", "L", "LR", nil]],
                    "tempoPercent": ["type": ["number", "null"]],
                    "mode": ["type": ["string", "null"], "enum": ["wait", "timed", nil]],
                    "lessonID": ["type": ["string", "null"]], "goal": ["type": ["string", "null"]],
                ], "required": ["kind", "fromBar", "toBar", "hand", "tempoPercent", "mode", "lessonID", "goal"],
                 "additionalProperties": false],
            ]],
        ],
        "required": ["on_topic", "reply", "action"],
        "additionalProperties": false,
    ]

    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        let result = try await client.chat(Self.messages(history: history, context: context, question: question),
                                           options: .init(model: model, schema: (name: "tutor_chat", schema: Self.schema),
                                                          reasoningEffort: "low", maxTokens: 2048, requestTimeout: 45))
        return (try? result.decode(TutorChatReply.self)) ?? TutorChatReply(onTopic: false, reply: "")
    }

    /// The instructions, the conversation, then the context (as data) with the new question.
    static func messages(history: [TutorChatTurn], context: TutorChatContext, question: String) -> [ChatMessage] {
        var messages: [ChatMessage] = [.system(TutorChatInstructions.musicOnly)]
        for turn in history {
            messages.append(ChatMessage(turn.role == .tutor ? .assistant : .user,
                                        [.text(turn.role == .app ? "App observation (data): " + turn.text : turn.text)]))
        }
        var parts: [ChatMessage.Part] = [.text("<context>\n\(context.prompt)\n</context>\n\nLearner's question: \(question)")]
        if let image = context.pageImage { parts.append(.image(image, mimeType: "image/jpeg")) }
        if let image = context.scoreImage { parts.append(.image(image, mimeType: "image/jpeg")) }
        messages.append(.user(parts))
        return messages
    }
}
#endif
