import Foundation
import PianoGraderCore

/// An app-owned audio sequencer. The host can enforce a playback lease around these operations.
@MainActor public protocol EarSequenceOutput: AnyObject {
    func start(_ notes: [NoteEvent]) -> Bool
    var position: TimeInterval? { get }
    func stop()
}

/// Notes use the engine's clock; the scheduler only observes completion, never schedules notes.
@MainActor public final class EarSequencedPlayback: EarPlayback {
    private let output: any EarSequenceOutput
    private let scheduler: any EarEventScheduler
    private let clock: () -> TimeInterval
    private let isAuthorized: () -> Bool
    private var event: (any EarScheduledEvent)?
    private var generation: UInt64 = 0

    public init(output: any EarSequenceOutput, scheduler: (any EarEventScheduler)? = nil,
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                isAuthorized: @escaping () -> Bool = { true }) {
        self.output = output; self.scheduler = scheduler ?? EarMainScheduler(); self.clock = clock; self.isAuthorized = isAuthorized
    }

    public func stop() {
        generation &+= 1
        event?.cancel(); event = nil
        output.stop()
    }

    public func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) {
        stop()
        guard isAuthorized() else { return }
        guard !notes.isEmpty, notes.allSatisfy({
            (0...127).contains($0.pitch) && $0.onset.isFinite && $0.offset.isFinite
                && $0.onset >= 0 && $0.offset > $0.onset && $0.offset < 120
        }) else { completion(.failure(.invalidSequence)); return }
        guard output.start(notes) else { completion(.failure(.unavailable)); return }
        observe(token: generation, started: clock(), duration: notes.map(\.offset).max()! + 0.08, completion: completion)
    }

    private func observe(token: UInt64, started: TimeInterval, duration: TimeInterval,
                         completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) {
        event = scheduler.schedule(after: 0.04) { [weak self] in
            guard let self, self.generation == token else { return }
            guard self.isAuthorized() else { self.stop(); return }
            let position = self.output.position ?? max(0, self.clock() - started)
            if position >= duration {
                self.stop()
                completion(.success(()))
            } else {
                self.observe(token: token, started: started, duration: duration, completion: completion)
            }
        }
    }
}
