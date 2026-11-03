#if os(macOS)
import Foundation
import PianoCatalog
import PianoGraderCore

extension PlaySession {
    /// Validate before changing tabs or stopping the existing lesson/tutor.
    @discardableResult
    func openCatalogPiece(_ url: URL, piece: CatalogPiece, tutored: Bool) -> Bool {
        do { try CatalogCache.validate(Data(contentsOf: url), for: piece) }
        catch { return false }
        // Run tab teardown synchronously, before installing the new reference and tutor.
        changingTabNow = true
        tab = .practice
        changingTabNow = false
        tabChanged()
        guard loadReference(url, title: piece.title) else { return false }
        if tutored { beginTutoring() }
        return true
    }
}
#endif
