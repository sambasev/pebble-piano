#if os(macOS)
import Foundation
import PianoGraderCore

/// The saved backing tracks, shared by the editor tab and the practice tab (main thread).
final class BackingStore: ObservableObject {
    let library: BackingTrackLibrary
    @Published private(set) var tracks: [BackingTrack] = []
    /// Bumped when links change, so views showing a link refresh.
    @Published private(set) var linksVersion = 0
    /// Called after a track is saved or deleted (its id).
    var onTrackChanged: ((UUID) -> Void)?

    init(library: BackingTrackLibrary = BackingTrackLibrary(directory: BackingTrackLibrary.defaultDirectory)) {
        self.library = library
        // The packaged app ships backing tracks (App/project.yml bundles BackingTracks/);
        // add any the library doesn't have yet. The Swift package executable has none.
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("BackingTracks", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) {
                library.installBundled(from: bundled, referenceFolder: resources.appendingPathComponent("Examples"))
            }
        }
        reload()
    }

    func reload() { tracks = library.tracks() }

    func track(_ id: UUID?) -> BackingTrack? {
        guard let id else { return nil }
        return tracks.first { $0.id == id } ?? library.track(id)
    }

    func save(_ track: BackingTrack) throws {
        try library.save(track)
        Usage.event("BackingTrack.saved")
        reload()
        onTrackChanged?(track.id)
    }

    func delete(_ id: UUID) throws {
        try library.delete(id)
        reload()
        linksVersion += 1
        onTrackChanged?(id)
    }

    func linkedTrackID(for key: String) -> UUID? { library.linkedTrackID(for: key) }

    func link(_ key: String, to id: UUID?) throws {
        try library.link(key, to: id)
        linksVersion += 1
    }

    func audioURL(for track: BackingTrack) -> URL? { library.resolveAudio(for: track) }
}
#endif
