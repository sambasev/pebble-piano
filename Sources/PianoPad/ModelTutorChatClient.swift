#if os(macOS)
import Foundation
import PianoAI
import PianoLessons

/// Ask your tutor, answered by Muse Spark (the tutor model), its reply constrained to
/// `{on_topic, reply, actions, suggestions}`. A reply that can't be read counts as off topic: the chat refuses
/// rather than show text that wasn't checked.
struct ModelTutorChatClient: TutorChatClient {
    let client: ModelClient
    let model: String

    static func configured() throws -> Self {
        Self(client: try ModelClient.configured(.meta), model: AISettings.shared.tutorModel)
    }

    /// Every action field, nullable when unused; all are required so the model always writes them.
    static var actionFields: [String: JSONValue] {
        playerActionFields.merging(libraryActionFields) { a, _ in a }.merging(demoActionFields) { a, _ in a }
            .merging(progressActionFields) { a, _ in a }
    }

    static let playerActionFields: [String: JSONValue] = [
        "kind": ["type": "string", "enum": .array(TutorChatAction.Kind.allCases.map { .string($0.rawValue) })],
        "fromBar": ["type": ["integer", "null"]], "toBar": ["type": ["integer", "null"]],
        "hand": ["type": ["string", "null"], "enum": ["R", "L", "LR", nil]],
        "tempoPercent": ["type": ["number", "null"]],
        "mode": ["type": ["string", "null"], "enum": ["wait", "timed", nil]],
        "lessonID": ["type": ["string", "null"]], "goal": ["type": ["string", "null"]],
    ]

    /// searchLibrary, openPiece, previewPiece and openBookPage.
    static let libraryActionFields: [String: JSONValue] = [
        "query": ["type": ["string", "null"]], "composer": ["type": ["string", "null"]],
        "difficulty": ["type": ["string", "null"], "enum": ["Elementary", "Intermediate", "Advanced", nil]],
        "pieceRef": ["type": ["string", "null"]], "page": ["type": ["integer", "null"]],
    ]

    /// practiceExercise, playNotes, highlight and the ear-training and sight-reading courses.
    static let demoActionFields: [String: JSONValue] = [
        "exercise": ["type": ["string", "null"],
                     "enum": .array(ExerciseGenerator.Kind.allCases.map { .string($0.rawValue) } + [.null])],
        "key": ["type": ["string", "null"]], "octaves": ["type": ["integer", "null"]],
        "notes": ["type": ["array", "null"], "items": ["type": "string"]],
        "tempoBPM": ["type": ["number", "null"]],
        "bars": ["type": ["array", "null"], "items": ["type": "integer"]],
        "keys": ["type": ["array", "null"], "items": ["type": "string"]],
        "level": ["type": ["integer", "null"]],
    ]

    /// setGoal's date and planSession.
    static let progressActionFields: [String: JSONValue] = [
        "goalDate": ["type": ["string", "null"]], "minutes": ["type": ["integer", "null"]],
        "planSteps": ["type": ["array", "null"], "items": ["type": "string"]],
    ]

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "on_topic": ["type": "boolean"],
            "reply": ["type": "string"],
            "actions": ["type": "array", "items": ["type": "object", "properties": .object(actionFields),
                                                    "required": .array(actionFields.keys.sorted().map { .string($0) }),
                                                    "additionalProperties": false]],
            "suggestions": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["on_topic", "reply", "actions", "suggestions"],
        "additionalProperties": false,
    ]

    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        let result = try await client.chat(Self.messages(history: history, context: context, question: question),
                                           options: .init(model: model, schema: (name: "tutor_chat", schema: Self.schema),
                                                          reasoningEffort: "low", maxTokens: 2048, requestTimeout: 45))
        return (try? result.decode(TutorChatReply.self)) ?? TutorChatReply(onTopic: false, reply: "")
    }

    func summarize(_ turns: [TutorChatTurn]) async throws -> String? {
        let transcript = turns.filter { !$0.refused }.suffix(TutorChatMemory.savedTurns).map { turn in
            "\(turn.role == .learner ? "Learner" : turn.role == .tutor ? "Teacher" : "App"): \(turn.text)"
        }.joined(separator: "\n")
        let result = try await client.chat([.system(TutorChatMemory.summaryInstructions),
                                            .user("<conversation>\n\(transcript)\n</conversation>")],
                                           options: .init(model: model, reasoningEffort: "low", maxTokens: 300, requestTimeout: 30))
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
