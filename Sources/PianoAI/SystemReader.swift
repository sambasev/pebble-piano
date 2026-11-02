import Foundation

/// Reads one system crop with a vision model (Muse Wonder by default), streamed.
/// The prompt and schema are the ones `scripts/ai_probe2.py` scored on the Beyer fixtures.
public struct SystemReader: Sendable {
    public let client: ModelClient
    public var model: String
    public var reasoningEffort: String
    /// The longest one read may take. A line usually takes one to two minutes; past this the
    /// server is holding the stream open with keepalives and no answer, so the read fails
    /// (and can be tried again) instead of spinning for ever.
    public var deadline: TimeInterval

    public init(client: ModelClient, model: String = MetaModels.wonder, reasoningEffort: String = "medium",
                deadline: TimeInterval = 300) {
        self.client = client
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.deadline = deadline
    }

    /// One system image (PNG) → its reading. `expectedMeasures`: how many bars were measured on
    /// the image, so the model doesn't stop after the first few (it sometimes does).
    /// `singleStaff`: the image is one staff on its own, all of it for one hand.
    public func read(png: Data, expectedMeasures: Int? = nil, singleStaff: Bool = false) async throws -> SystemReading {
        var prompt = Self.prompt
        if singleStaff { prompt += "\n" + Self.singleStaffNote }
        if let n = expectedMeasures, n > 0 {
            prompt += "\nThe bar lines measured in this image give \(n) measure\(n == 1 ? "" : "s"): read every one of them, "
                + "left to right (check against the image if a bar line seems missing or extra)."
        }
        let result = try await client.chat(
            [.user([.text(prompt), .image(png, mimeType: "image/png")])],
            options: .init(model: model, schema: ("Systems", Self.schema), reasoningEffort: reasoningEffort,
                           stream: true, deadline: deadline))
        return try result.decode(SystemReading.self)
    }

    public static let prompt = """
    This image is one or more systems of beginner piano music: an upper and a lower staff joined by a brace.
    For every measure, left to right, list each staff's notes and rests in order.

    Give each note's vertical POSITION on its own staff as an integer, counted in steps (lines and spaces):
      0 = bottom line, 1 = space above the bottom line, 2 = second line, 3 = second space, 4 = middle line,
      5 = third space, 6 = fourth line, 7 = top space, 8 = top line, 9 = space just above the top line,
      10 = first ledger line above, -1 = space just below the bottom line, -2 = first ledger line below.
    Read each staff's clef from the image; in this book BOTH staves are often treble. Beginner music sometimes
    prints no clef (a letter like "G" may mark the first note instead): a staff with no clef is treble.
    Durations: whole (hollow, no stem), half (hollow, stem), quarter (filled, stem), eighth (filled, flag or beam).
    finger = a printed fingering number (1-5) above or below that note, else null. Ignore text, slurs and dynamics.
    Count the barlines first so the number of measures is right.
    """

    static let singleStaffNote = """
    This image is ONE staff on its own, not a pair: put all of its notes in "upper" and give "lower" clef treble
    and no notes. Notes or text from a neighbouring staff cut off at the image's edge are not part of it.
    """

    static let staffSchema: JSONValue = [
        "type": "object", "additionalProperties": false, "required": ["clef", "notes"],
        "properties": [
            "clef": ["type": "string", "enum": ["treble", "bass"]],
            "notes": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["rest", "position", "duration", "dotted", "accidental", "finger"],
                "properties": [
                    "rest": ["type": "boolean"],
                    "position": ["type": "integer"],
                    "duration": ["type": "string", "enum": ["whole", "half", "quarter", "eighth", "sixteenth"]],
                    "dotted": ["type": "boolean"],
                    "accidental": ["type": "string", "enum": ["none", "sharp", "flat", "natural"]],
                    "finger": ["type": ["integer", "null"]],
                ],
            ]],
        ],
    ]

    public static let schema: JSONValue = [
        "type": "object", "additionalProperties": false, "required": ["measureCount", "measures"],
        "properties": [
            "measureCount": ["type": "integer"],
            "measures": ["type": "array", "items": [
                "type": "object", "additionalProperties": false, "required": ["upper", "lower"],
                "properties": ["upper": staffSchema, "lower": staffSchema],
            ]],
        ],
    ]
}
