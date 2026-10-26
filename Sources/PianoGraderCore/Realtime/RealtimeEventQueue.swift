import Atomics
import Dispatch
import Foundation

/// Hands values from a realtime thread to ordinary code.
///
/// The realtime side gets a `Poster`: a plain struct (no object references held strongly,
/// nothing reference-counted on use) whose `post` writes into a preallocated lock-free ring
/// and signals a semaphore. Neither step allocates or takes a lock; signalling a dispatch
/// semaphore only enters the kernel when the worker is waiting, which is the accepted way
/// to wake another thread from an audio or MIDI callback.
///
/// A worker thread wakes up, drains everything posted so far, and calls `handler` with the
/// batch, in order. The handler runs off the realtime thread and may allocate, lock and
/// dispatch freely.
///
/// Lifetime: stop whatever owns the realtime callback (stop the audio engine, dispose the
/// MIDI client) before releasing the queue, so no `post` can run after `deinit`.
public final class RealtimeEventQueue<Element> {
    public struct Poster {
        fileprivate let ring: SPSCRing<Element>
        fileprivate let wake: Unmanaged<DispatchSemaphore>
        fileprivate let dropped: UnsafeAtomic<Int>

        /// Whether a `post` now would be kept. Realtime-safe. Only the posting thread adds
        /// values, so true stays true until it posts.
        @inline(__always)
        public var hasRoom: Bool { ring.freeCount > 0 }

        /// Realtime-safe. Returns false if the ring was full and the value was dropped.
        @inline(__always) @discardableResult
        public func post(_ element: Element) -> Bool {
            let ok = ring.push(element)
            if !ok { dropped.wrappingIncrement(ordering: .relaxed) }
            _ = wake._withUnsafeGuaranteedRef { $0.signal() }
            return ok
        }
    }

    public let poster: Poster
    private let ring: SPSCRing<Element>
    private let wake: DispatchSemaphore
    private let finished: DispatchSemaphore
    private let running: UnsafeAtomic<Bool>
    private let dropped: UnsafeAtomic<Int>

    /// - Parameters:
    ///   - capacity: values that can wait before new ones are dropped.
    ///   - blank: any value of the element type (fills the unused storage).
    ///   - name: the worker thread's name, for debugging.
    ///   - handler: called on the worker thread with each batch of posted values, in order.
    public init(capacity: Int, blank: Element, name: String,
                qos: QualityOfService = .userInteractive,
                handler: @escaping ([Element]) -> Void) {
        let ring = SPSCRing.allocate(minimumCapacity: capacity, blank: blank)
        let wake = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let running = UnsafeAtomic<Bool>.create(true)
        let dropped = UnsafeAtomic<Int>.create(0)
        self.ring = ring
        self.wake = wake
        self.finished = finished
        self.running = running
        self.dropped = dropped
        // The poster refers to the semaphore without retaining it; `self.wake` keeps it alive.
        poster = Poster(ring: ring, wake: Unmanaged.passUnretained(wake), dropped: dropped)
        let thread = Thread {
            var batch: [Element] = []
            batch.reserveCapacity(ring.capacity)
            while running.load(ordering: .acquiring) {
                wake.wait()
                batch.removeAll(keepingCapacity: true)
                while let element = ring.pop() { batch.append(element) }
                if !batch.isEmpty { handler(batch) }
            }
            finished.signal()
        }
        thread.name = name
        thread.qualityOfService = qos
        thread.start()
    }

    /// Values dropped because the ring was full.
    public var droppedCount: Int { dropped.load(ordering: .relaxed) }

    deinit {
        running.store(false, ordering: .releasing)
        wake.signal()
        finished.wait()
        ring.deallocate()
        running.destroy()
        dropped.destroy()
    }
}
