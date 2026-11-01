import Foundation

extension MIDISequence {
    /// Which file track holds each hand, for two-staff piano music: the track with the higher
    /// mean pitch is the right hand. Nil unless exactly two tracks have notes (one staff, or a
    /// file with more parts, can't be split into hands this way). Book imports write one track
    /// per staff, upper staff first.
    public var handTracks: [Hand: Int]? {
        let byTrack = Dictionary(grouping: notes, by: \.track)
        guard byTrack.count == 2 else { return nil }
        let ranked = byTrack
            .map { (track: $0.key, mean: Double($0.value.map(\.pitch).reduce(0, +)) / Double($0.value.count)) }
            .sorted { ($0.mean, -$0.track) > ($1.mean, -$1.track) }
        return [.right: ranked[0].track, .left: ranked[1].track]
    }

    /// Whether the music can be practised one hand at a time.
    public var hasTwoHands: Bool { handTracks != nil }

    /// Only one hand's notes (`.both`, or music that can't be split, is returned unchanged).
    public func hand(_ hand: Hand?) -> MIDISequence {
        guard let hand, hand != .both, let track = handTracks?[hand] else { return self }
        var copy = self
        copy.notes = notes.filter { $0.track == track }
        return copy
    }

    /// The hand a note belongs to, when the music has two hands.
    public func hand(of note: NoteEvent) -> Hand? {
        guard let tracks = handTracks else { return nil }
        return tracks[.right] == note.track ? .right : tracks[.left] == note.track ? .left : nil
    }
}
