import Atomics

/// A lock-free ring buffer for one producer thread and one consumer thread.
///
/// Built to be used from realtime threads (an audio render callback, a CoreMIDI read block):
/// once allocated, `push`/`pop` never allocate, lock, call into the Objective-C runtime or
/// touch reference counts. The ring is a plain struct of pointers, so copying it into a
/// closure captures no object. Whoever calls `allocate` owns the memory and must call
/// `deallocate()` once neither thread can use the ring any more.
///
/// `Element` must be a trivial type (no references, no non-trivial copy), checked on allocate.
public struct SPSCRing<Element> {
    public let capacity: Int
    private let mask: Int
    private let buffer: UnsafeMutablePointer<Element>
    /// Total elements ever written (producer-owned).
    private let head: UnsafeAtomic<Int>
    /// Total elements ever read (consumer-owned).
    private let tail: UnsafeAtomic<Int>

    /// - Parameters:
    ///   - minimumCapacity: rounded up to a power of two.
    ///   - blank: value the storage starts filled with.
    public static func allocate(minimumCapacity: Int, blank: Element) -> SPSCRing {
        precondition(_isPOD(Element.self), "SPSCRing needs a trivial element type")
        var capacity = 1
        while capacity < max(1, minimumCapacity) { capacity <<= 1 }
        let buffer = UnsafeMutablePointer<Element>.allocate(capacity: capacity)
        buffer.initialize(repeating: blank, count: capacity)
        return SPSCRing(capacity: capacity, mask: capacity - 1, buffer: buffer,
                        head: .create(0), tail: .create(0))
    }

    private init(capacity: Int, mask: Int, buffer: UnsafeMutablePointer<Element>,
                 head: UnsafeAtomic<Int>, tail: UnsafeAtomic<Int>) {
        self.capacity = capacity
        self.mask = mask
        self.buffer = buffer
        self.head = head
        self.tail = tail
    }

    /// Frees the storage. Only once both threads have stopped using the ring.
    public func deallocate() {
        buffer.deallocate()
        head.destroy()
        tail.destroy()
    }

    // MARK: Producer side

    /// Space left for the producer (may be larger by the time it writes, never smaller).
    @inline(__always)
    public var freeCount: Int {
        capacity - (head.load(ordering: .relaxed) &- tail.load(ordering: .acquiring))
    }

    /// Adds one element. Returns false (dropping it) when the ring is full.
    @inline(__always) @discardableResult
    public func push(_ element: Element) -> Bool {
        let h = head.load(ordering: .relaxed)
        guard h &- tail.load(ordering: .acquiring) < capacity else { return false }
        buffer[h & mask] = element
        head.store(h &+ 1, ordering: .releasing)
        return true
    }

    /// Copies up to `count` elements taken every `stride` elements from `source`
    /// (stride 2 picks one channel of interleaved stereo). Returns how many were written.
    @inline(__always) @discardableResult
    public func push(from source: UnsafePointer<Element>, count: Int, stride: Int = 1) -> Int {
        let h = head.load(ordering: .relaxed)
        let free = capacity - (h &- tail.load(ordering: .acquiring))
        let n = min(count, free)
        guard n > 0 else { return 0 }
        var i = 0
        while i < n {
            buffer[(h &+ i) & mask] = source[i &* stride]
            i &+= 1
        }
        head.store(h &+ n, ordering: .releasing)
        return n
    }

    // MARK: Consumer side

    /// Elements waiting to be read.
    @inline(__always)
    public var count: Int {
        head.load(ordering: .acquiring) &- tail.load(ordering: .relaxed)
    }

    /// Takes the oldest element, or nil when empty.
    @inline(__always)
    public func pop() -> Element? {
        let t = tail.load(ordering: .relaxed)
        guard head.load(ordering: .acquiring) &- t > 0 else { return nil }
        let element = buffer[t & mask]
        tail.store(t &+ 1, ordering: .releasing)
        return element
    }

    /// Takes up to `destination.count` elements, oldest first. Returns how many were read.
    @inline(__always) @discardableResult
    public func pop(into destination: UnsafeMutableBufferPointer<Element>) -> Int {
        let t = tail.load(ordering: .relaxed)
        let n = min(destination.count, head.load(ordering: .acquiring) &- t)
        guard n > 0, let base = destination.baseAddress else { return 0 }
        var i = 0
        while i < n {
            base[i] = buffer[(t &+ i) & mask]
            i &+= 1
        }
        tail.store(t &+ n, ordering: .releasing)
        return n
    }
}
