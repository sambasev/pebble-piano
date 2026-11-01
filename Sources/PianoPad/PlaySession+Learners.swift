#if os(macOS)
import AppKit
import Foundation
import PianoGraderCore
import PianoLessons
import PianoPadState
import UniformTypeIdentifiers

/// Learners: who is playing, their settings and their recent pieces. The device-wide state
/// (volumes, mic gate, calibration) is untouched by any of this.
extension PlaySession {
    // MARK: Switching and managing learners

    /// The launch screens are up: no learner yet ("Add learner"), or more than one and nobody
    /// has said who's playing.
    var isChoosingLearner: Bool { learners.isEmpty || needsLearnerPick }

    /// From the launch picker: start as this learner.
    func pickLearner(_ id: UUID) {
        switchLearner(to: id)
        needsLearnerPick = false
    }

    /// Offer the 30-second mic calibration after adding the first learner: only when the Mac
    /// isn't calibrated and there's no MIDI keyboard (which needs no calibration).
    var shouldOfferCalibration: Bool { !isCalibrated && midiSources.isEmpty }

    /// Makes `id` the active learner. Stops whatever is playing or recording (the take is
    /// discarded until takes are stored per learner), then loads their settings and recent pieces.
    func switchLearner(to id: UUID) {
        guard id != learner?.id else { return }
        stopForLearnerChange()
        do {
            try learnerStore.setActive(id)
        } catch {
            message = "Couldn't switch learner: \(error.localizedDescription)"
            refreshEarLearner()
            return
        }
        applyActiveLearner()
    }

    /// Adds a learner and switches to them. Returns nil (with a message) if it couldn't.
    @discardableResult
    func addLearner(name: String, avatar: String = Learner.defaultAvatar, kind: Learner.Kind,
                    level: Learner.Level? = nil) -> Learner? {
        do {
            let new = try learnerStore.add(name: name, avatar: avatar, kind: kind, level: level)
            learners = learnerStore.learners
            switchLearner(to: new.id)
            needsLearnerPick = false
            return new
        } catch LearnerStoreError.emptyName {
            message = "A learner needs a name."
        } catch {
            message = "Couldn't add \(name): \(error.localizedDescription)"
        }
        return nil
    }

    func renameLearner(_ id: UUID, to name: String) {
        updateLearner { try learnerStore.rename(id, to: name) }
    }

    func setLearnerAvatar(_ id: UUID, to avatar: String) {
        updateLearner { try learnerStore.setAvatar(id, to: avatar) }
    }

    func setLearnerKind(_ id: UUID, to kind: Learner.Kind) {
        updateLearner { try learnerStore.setKind(id, to: kind) }
    }

    /// Deletes a learner and their folder. Deleting the active learner switches to the first
    /// one left, or to no learner.
    func deleteLearner(_ id: UUID) {
        let wasActive = id == learner?.id
        if wasActive { stopForLearnerChange() }
        do {
            try learnerStore.delete(id)
            // Drop pending ear saves too: a retry must never recreate a deleted learner folder.
            resetEarProgress(for: id)
        } catch {
            message = "Couldn't delete the learner: \(error.localizedDescription)"
            return
        }
        if wasActive {
            applyActiveLearner()
        } else {
            learners = learnerStore.learners
        }
    }

    // MARK: Settings

    /// Saves `learnerSettings` for the active learner. With no learner, settings live only in
    /// memory until one is added.
    func saveLearnerSettings() {
        guard !applyingLearnerSettings, let learner else { return }
        do {
            try learnerStore.save(learnerSettings, for: learner.id)
        } catch {
            message = "Couldn't save \(learner.name)'s settings: \(error.localizedDescription)"
        }
    }

    /// Loads the active learner (from the store) and applies their settings and recent pieces.
    func applyActiveLearner() {
        learners = learnerStore.learners
        learner = learnerStore.activeLearner
        learnerSettings = learner.map { learnerStore.settings(for: $0.id) } ?? LearnerSettings()
        applyingLearnerSettings = true
        strictness = Self.strictness(from: learnerSettings)
        customPlayAlong = Self.customPlayAlong(from: learnerSettings)
        missMode = Self.missMode(from: learnerSettings)
        applyingLearnerSettings = false
        setModeNow(Self.practiceMode(from: learnerSettings))
        configureJudge()
        rebuildPieces()
        applyInputChoice()
        refreshEarLearner()
    }

    private func stopForLearnerChange() {
        lessonRunner.learnerWillChange()
        stopEarForLearnerChange()
        endTutoring()
        stopPlayAlong(discard: true)
        stopAudition()
        resetTake()
    }

    private func updateLearner(_ change: () throws -> Void) {
        do {
            try change()
        } catch LearnerStoreError.emptyName {
            message = "A learner needs a name."
        } catch {
            message = "Couldn't update the learner: \(error.localizedDescription)"
        }
        learners = learnerStore.learners
        if let id = learner?.id { learner = learnerStore.learner(id) }
    }

    // MARK: Recent pieces

    /// A short name for a MIDI file: its title up to " - ", else the file name.
    static func pieceName(_ url: URL, title: String?) -> String {
        if let title, !title.isEmpty {
            return title.components(separatedBy: " - ").first ?? title
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Puts a MIDI file the learner opened at the top of their recent pieces, with a bookmark
    /// so the sandboxed app can reopen it in a later launch. Examples aren't recorded.
    func rememberPiece(_ url: URL, title: String?) {
        let path = url.standardizedFileURL.path
        guard !examplePieces.contains(where: { $0.standardizedFileURL.path == path }),
              let id = try? PieceID.file(at: url) else {
            rebuildPieces()
            return
        }
        let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        learnerSettings.recentPieces.removeAll { $0.path == path }
        learnerSettings.remember(RecentPiece(id: id, bookmark: bookmark, path: path, title: title))
        saveLearnerSettings()
        rebuildPieces()
    }

    func forgetPiece(_ url: URL) {
        let path = url.standardizedFileURL.path
        learnerSettings.recentPieces.removeAll { $0.path == path }
        saveLearnerSettings()
        rebuildPieces()
    }

    /// The picker's list: the learner's recent files first, then the examples. Recent files
    /// that can no longer be found drop off; moved files (found through their bookmark) keep
    /// their place under the new path.
    func rebuildPieces() {
        var kept: [RecentPiece] = []
        var seen = Set<String>()
        var list: [(name: String, url: URL)] = []
        for var piece in learnerSettings.recentPieces {
            guard let url = resolveRecent(&piece) else { continue }
            kept.append(piece)
            guard seen.insert(url.path).inserted else { continue }
            let title = piece.title ?? (try? MIDIFile.read(url: url))?.title
            list.append((Self.pieceName(url, title: title), url))
        }
        for url in examplePieces {
            let url = url.standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            list.append((Self.pieceName(url, title: (try? MIDIFile.read(url: url))?.title), url))
        }
        pieces = list

        // Let go of files no longer listed.
        for (path, url) in accessedRecentFiles where !seen.contains(path) {
            url.stopAccessingSecurityScopedResource()
            accessedRecentFiles[path] = nil
        }
        if kept != learnerSettings.recentPieces {
            learnerSettings.recentPieces = kept
            saveLearnerSettings()
        }
    }

    /// The file a recent piece refers to: through its bookmark (starting security-scoped
    /// access, and refreshing a stale bookmark), else its saved path. Nil if it can't be found.
    private func resolveRecent(_ piece: inout RecentPiece) -> URL? {
        let fm = FileManager.default
        if let bookmark = piece.bookmark {
            var stale = false
            if let found = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                    relativeTo: nil, bookmarkDataIsStale: &stale) {
                let url = found.standardizedFileURL
                if accessedRecentFiles[url.path] == nil, found.startAccessingSecurityScopedResource() {
                    accessedRecentFiles[url.path] = found
                }
                if stale, let fresh = try? found.bookmarkData(options: .withSecurityScope,
                                                              includingResourceValuesForKeys: nil, relativeTo: nil) {
                    piece.bookmark = fresh
                }
                if fm.fileExists(atPath: url.path) {
                    piece.path = url.path
                    return url
                }
            }
        }
        if let path = piece.path, fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return nil
    }

    // MARK: History (takes and progress)

    /// The piece being played, for keying takes and progress: a book passage by book and
    /// passage ID (as backing-track links are), else the MIDI file by its contents.
    var currentPieceID: PieceID? {
        if let lessonPiece { return lessonPiece }
        if let passage, let book {
            return PieceID(rawValue: BackingLinkKey.passage(book: book.annotations.pdf, id: passage.id))
        }
        return referenceURL.flatMap { try? PieceID.file(at: $0) }
    }

    /// Saves the take just graded, with its report, to the active learner's history.
    /// Without a learner (or a piece) nothing is saved.
    func recordGradedTake() {
        guard let learner, let piece = currentPieceID, let report, (!lastTake.isEmpty || tutor != nil) else { return }
        if !isInLesson {
            Usage.event("Practice.graded", ["mode": mode.rawValue,
                                            "piece": passage != nil ? "book" : "midi",
                                            "backingTrack": hasBackingTrack ? "yes" : "no"])
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let saved = try learnerStore.history(for: learner.id).record(
                piece: piece,
                midi: MIDIFile.write(notes: lastTake),
                report: encoder.encode(report),
                score: report.notes.score,
                passed: report.passed && (tutor == nil || (report.timing != nil && mode == .playAlong && tempoPercent >= 99.5 && replaysThisTake == 0)), contributesToProgress: tutor == nil || tutorAttempt?.kind == .assessment || tutorAttempt?.kind == .perform)
            if let attempt = tutorAttempt {
                let metadata = TutorAttemptContext(exercise: attempt, actualTempoPercent: tempoPercent,
                    mode: mode.rawValue, printedMeasures: attempt.measures.map { passage?.printedMeasure(forPlayed: $0) ?? $0 },
                    stars: tutorPerformStars)
                try JSONEncoder().encode(metadata).write(to: saved.reportURL.deletingPathExtension().appendingPathExtension("tutor.json"), options: .atomic)
            }
        } catch {
            message = "Couldn't save the take to \(learner.name)'s history: \(error.localizedDescription)"
        }
    }

    /// Clears a learner's takes and progress; their settings stay.
    func resetProgress(for id: UUID) {
        do {
            try learnerStore.history(for: id).reset()
            resetEarProgress(for: id)
        } catch {
            message = "Couldn't reset progress: \(error.localizedDescription)"
        }
    }

    /// Writes the learner's folder (settings, takes, progress) as a zip, through a save panel.
    func exportLearner(_ id: UUID) {
        guard let learner = learnerStore.learner(id) else { return }
        let folder = learnerStore.folder(for: id)
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            // Nothing saved yet: write the (default) settings so there is something to export.
            try? learnerStore.save(learnerStore.settings(for: id), for: id)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(learner.name) - PerfectPiano.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // Reading a folder "for uploading" hands back a zip of it; it works in the sandbox.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: zip, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            message = "Couldn't export \(learner.name): \(error.localizedDescription)"
        } else {
            message = "Exported \(learner.name) to \(destination.lastPathComponent)."
        }
    }
}
#endif
