#if os(macOS)
import Foundation
import PianoCatalog
import SwiftUI

@MainActor
final class MusicLibraryModel: ObservableObject {
    let catalog: MusicCatalog?
    let cache: CatalogCache
    @Published var query = ""
    @Published var composer: String?
    @Published var difficulty: CatalogPiece.Difficulty?
    @Published var downloadedOnly = false
    @Published var selectedID: String?
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var previewingID: String?
    @Published private(set) var downloadingID: String?
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private var previewGeneration = UUID()
    private var stopPreviewPlayback: (() -> Void)?
    private var requestID: UUID?
    private var task: Task<Void, Never>?

    init(catalog: MusicCatalog? = nil, cache: CatalogCache = CatalogCache()) {
        self.cache = cache
        do { self.catalog = try catalog ?? MusicCatalog.bundled() }
        catch { self.catalog = nil; self.error = error.localizedDescription }
    }

    var pieces: [CatalogPiece] { catalog?.pieces ?? [] }
    var composers: [String] { Set(pieces.map(\.composer)).sorted() }
    var filtered: [CatalogPiece] {
        pieces.filter {
            $0.matches(query: query, composer: composer, difficulty: difficulty)
                && (!downloadedOnly || downloaded.contains($0.id))
        }
    }
    var selected: CatalogPiece? { filtered.first { $0.id == selectedID } ?? filtered.first }

    func refreshDownloads() async {
        downloaded = await cache.downloadedIDs(in: pieces)
    }

    /// The piece's MIDI file to preview, downloaded (and checked) first if need be.
    func previewFile(_ piece: CatalogPiece) async -> URL? {
        guard let url = try? await cache.prepare(piece) else { return nil }
        downloaded.insert(piece.id)
        return url
    }

    func cancel() {
        requestID = nil
        task?.cancel(); task = nil
        downloadingID = nil; progress = nil
        stopPreview()
    }

    private func stopPreview() {
        previewGeneration = UUID()
        previewingID = nil
        let stop = stopPreviewPlayback
        stopPreviewPlayback = nil
        stop?()
    }

    /// Audition in place using the same validated cache as practice. Tapping again stops it.
    func preview(_ piece: CatalogPiece, play: @escaping (URL, @escaping () -> Void) -> Bool,
                 stop: @escaping () -> Void) {
        if previewingID == piece.id { cancel(); return }
        prepare(piece, failureMessage: "Couldn't preview this piece. Check your audio output and try again.") { [weak self] url in
            guard let self else { return false }
            let generation = self.previewGeneration
            self.stopPreviewPlayback = stop
            return play(url) { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.previewingID = nil
                self.stopPreviewPlayback = nil
            }
        }
        previewingID = piece.id
    }

    /// `onFailure` hears of a download that failed (not one cancelled).
    func open(_ piece: CatalogPiece, onOpen: @escaping (URL) -> Bool, onFailure: (() -> Void)? = nil) {
        prepare(piece, failureMessage: "Couldn't open this piece. Please try again.", onReady: onOpen, onFailure: onFailure)
    }

    private func prepare(_ piece: CatalogPiece, failureMessage: String, onReady: @escaping (URL) -> Bool,
                         onFailure: (() -> Void)? = nil) {
        cancel()
        error = nil
        let token = UUID()
        requestID = token; downloadingID = piece.id
        task = Task { [weak self, cache] in
            do {
                let url = try await cache.prepare(piece) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.requestID == token else { return }
                        self.progress = value
                    }
                }
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }
                self.downloaded.insert(piece.id)
                self.requestID = nil; self.downloadingID = nil; self.task = nil
                if !onReady(url) {
                    self.stopPreview()
                    self.error = failureMessage
                }
            } catch {
                guard let self, self.requestID == token else { return }
                self.requestID = nil; self.downloadingID = nil; self.task = nil
                self.stopPreview()
                if !(error is CancellationError) {
                    self.error = "\(error.localizedDescription) Select a piece and try again."
                    onFailure?()
                }
            }
        }
    }
}
#endif
