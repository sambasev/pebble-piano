import Foundation
import PianoGraderCore
#if canImport(AVFoundation)
import PianoGraderIO
#endif

public enum EarPlaybackError: Error, LocalizedError {
    case unavailable, invalidSequence
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Piano audio could not start. Check your sound output in System Settings, then press Play to retry."
        case .invalidSequence: return "This example could not be played. Select another stage and try again."
        }
    }
}

@MainActor public protocol EarPlayback: AnyObject {
    func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void)
    func stop()
}

@MainActor public protocol EarNoteOutput: AnyObject {
    func noteOn(pitch: Int, velocity: Int)
    func noteOff(pitch: Int)
    func allNotesOff()
}

@MainActor public protocol EarScheduledEvent: AnyObject { func cancel() }

@MainActor public protocol EarEventScheduler {
    func schedule(after seconds: Double, action: @escaping @MainActor () -> Void) -> any EarScheduledEvent
}

@MainActor private final class TaskEvent: EarScheduledEvent {
    var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil }
}

@MainActor public struct EarMainScheduler: EarEventScheduler {
    public init() {}
    public func schedule(after seconds: Double, action: @escaping @MainActor () -> Void) -> any EarScheduledEvent {
        let event = TaskEvent()
        event.task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return event
    }
}

#if canImport(AVFoundation)
@MainActor private final class EarPianoOutput: EarNoteOutput {
    let synth: PianoSynth
    init?() {
        guard let synth = PianoSynth() else { return nil }
        self.synth = synth
    }
    func noteOn(pitch: Int, velocity: Int) { synth.noteOn(pitch: pitch, velocity: velocity) }
    func noteOff(pitch: Int) { synth.noteOff(pitch: pitch) }
    func allNotesOff() { synth.allNotesOff() }
}
#endif

/// All sampler access is on the main actor. Every callback also checks its playback generation:
/// even an already-dequeued callback cannot affect notes from a newer Play request.
@MainActor public final class EarPlaybackController: EarPlayback {
    private let scheduler: any EarEventScheduler
    private let makeOutput: @MainActor () -> (any EarNoteOutput)?
    private var output: (any EarNoteOutput)?
    private var generation: UInt64 = 0
    private var events: [any EarScheduledEvent] = []

    public convenience init() {
        self.init(scheduler: EarMainScheduler(), makeOutput: {
            #if canImport(AVFoundation)
            return EarPianoOutput()
            #else
            return nil
            #endif
        })
    }

    public init(scheduler: any EarEventScheduler, makeOutput: @escaping @MainActor () -> (any EarNoteOutput)?) {
        self.scheduler = scheduler
        self.makeOutput = makeOutput
    }

    public func stop() {
        generation &+= 1
        events.forEach { $0.cancel() }
        events.removeAll()
        output?.allNotesOff()
    }

    public func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) {
        stop()
        guard !notes.isEmpty, notes.allSatisfy({
            (0...127).contains($0.pitch) && (1...127).contains($0.velocity)
                && $0.onset.isFinite && $0.offset.isFinite && $0.onset >= 0
                && $0.offset > $0.onset && $0.offset <= 120
        }) else { completion(.failure(.invalidSequence)); return }
        if output == nil { output = makeOutput() }
        guard output != nil else { completion(.failure(.unavailable)); return }
        let token = generation
        struct Event { let time: Double; let pitch: Int; let velocity: Int; let isOn: Bool }
        let noteEvents = notes.flatMap { note in
            [Event(time: note.onset, pitch: note.pitch, velocity: note.velocity, isOn: true),
             Event(time: note.offset, pitch: note.pitch, velocity: 0, isOn: false)]
        }.sorted { a, b in
            if a.time != b.time { return a.time < b.time }
            if a.isOn != b.isOn { return !a.isOn }
            return a.pitch < b.pitch
        }
        for noteEvent in noteEvents {
            events.append(scheduler.schedule(after: noteEvent.time) { [weak self] in
                guard let self, self.generation == token else { return }
                if noteEvent.isOn { self.output?.noteOn(pitch: noteEvent.pitch, velocity: noteEvent.velocity) }
                else { self.output?.noteOff(pitch: noteEvent.pitch) }
            })
        }
        events.append(scheduler.schedule(after: (notes.map(\.offset).max() ?? 0) + 0.08) { [weak self] in
            guard let self, self.generation == token else { return }
            self.stop()
            completion(.success(()))
        })
    }
}
