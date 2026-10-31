import Foundation

/// How long a timed Continue waits before going on by itself. A timed Continue is used only
/// where the learner just succeeded and there is one sensible next step; choices, failures
/// and anything that leaves the lesson stay manual. See docs/design/beginner-journeys.md
/// ("Auto-progress").
public enum AutoAdvance {
    public enum Moment: Equatable, Sendable {
        /// A pick made on a setup step (teacher, goal song): time to change your mind.
        case choiceMade
        /// A check passed (room noise measured, Bluetooth piano connected).
        case checkPassed
        /// A setup screen with a sentence or two to read (welcome, "All set").
        case setupInfo
        /// A listen or song stage finished; the next stage is suggested.
        case stageDone
        /// The warm-up went fine; on to the coach's page.
        case warmUpDone
        /// The strict teacher opens the drill by herself once the results have been seen.
        case drillStarts
        /// A page finished; on to the next page.
        case pageDone
        /// A card to read before going on (explain without a note to play, concept card).
        case reading(words: Int)
    }

    /// Children get longer: reading is slower and the button is a surprise the first time.
    public static let childFactor = 1.5

    public static func seconds(_ moment: Moment, child: Bool = false) -> Double {
        let base: Double
        switch moment {
        case .choiceMade: base = 1.5
        case .checkPassed: base = 2.5
        case .setupInfo: base = 4
        case .stageDone: base = 3
        case .warmUpDone: base = 3
        case .drillStarts: base = 4
        case .pageDone: base = 5
        case .reading(let words):
            // About 3.5 words a second, plus a moment to look at the keys.
            base = min(8, max(3, 1.5 + Double(words) / 3.5))
        }
        return child ? base * childFactor : base
    }

    /// Words in a card's text, for `.reading`.
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
