#if os(macOS)
import AppKit
import Foundation
import PianoLessons

/// Guided tours: which one fits the screen, starting one the first time, and moving through it.
/// What has been seen is kept per learner, in their settings.
extension PlaySession {
    /// The tour for what's on screen now.
    var currentScreenTour: TourID {
        switch tab {
        case .learn: return lessonRunner.page != nil && lessonRunner.result == nil ? .lessonPage : .learnMap
        case .practice: return .practice
        case .musicLibrary: return .musicLibrary
        case .books: return .books
        case .backingTracks: return backingEditor.draft != nil ? .backingEditor : .backingTracks
        }
    }

    /// Starts `tour` if this learner hasn't seen it, once the screen has settled (so its parts
    /// have reported where they are), and only if nothing else wants their attention.
    func startTourIfNew(_ tour: TourID) {
        guard !learnerSettings.hasSeenTour(tour.rawValue) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.currentScreenTour == tour, self.canStartTourByItself,
                  !self.learnerSettings.hasSeenTour(tour.rawValue) else { return }
            self.startTour(tour)
        }
    }

    /// Not over the learner gate or a sheet, nor in the middle of playing.
    private var canStartTourByItself: Bool {
        activeTour == nil && !isChoosingLearner && !isPlayingAlong && !isAuditioning && phase != .recording
            && NSApp.keyWindow?.attachedSheet == nil && NSApp.modalWindow == nil
    }

    /// Plays `tour` from the start, seen or not (the ? button).
    func startTour(_ tour: TourID) {
        tourStep = 0
        tourStepCount = tour.steps.count
        tourLetsYouPlay = false
        activeTour = tour
    }

    func nextTourStep() {
        if tourStep + 1 < tourStepCount { tourStep += 1 } else { endTour() }
    }

    func previousTourStep() {
        if tourStep > 0 { tourStep -= 1 }
    }

    /// Done or skipped: either way it won't start by itself again for this learner.
    func endTour() {
        guard let tour = activeTour else { return }
        activeTour = nil
        learnerSettings.markTourSeen(tour.rawValue)
        saveLearnerSettings()
    }

    /// Every tour starts by itself again, for the active learner.
    func resetTours() {
        learnerSettings.seenTours = []
        saveLearnerSettings()
        startTourIfNew(currentScreenTour)
    }

    /// While a tour runs, keys move it (Return/→ on, ← back, Esc skip) instead of playing.
    /// Returns true when the tour took the key: every key, except note keys on a step that
    /// asks you to try the keyboard.
    func handleTourKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76, 124, 49: nextTourStep()  // Return, Enter, →, Space
        case 123: previousTourStep()           // ←
        case 53: endTour()                     // Esc
        default: return !tourLetsYouPlay
        }
        return true
    }
}
#endif
