/// A set of MIDI pitches (0–127) in two machine words: no allocation, cheap to copy,
/// safe to use on a realtime thread. Pitches outside 0–127 are ignored.
public struct PitchSet: Hashable, Sendable {
    public private(set) var low: UInt64 = 0
    public private(set) var high: UInt64 = 0

    public init() {}

    public init<S: Sequence>(_ pitches: S) where S.Element == Int {
        for p in pitches { insert(p) }
    }

    @inline(__always)
    public func contains(_ pitch: Int) -> Bool {
        guard (0...127).contains(pitch) else { return false }
        return pitch < 64 ? low & (1 << UInt64(pitch)) != 0 : high & (1 << UInt64(pitch - 64)) != 0
    }

    @inline(__always)
    public mutating func insert(_ pitch: Int) {
        guard (0...127).contains(pitch) else { return }
        if pitch < 64 { low |= 1 << UInt64(pitch) } else { high |= 1 << UInt64(pitch - 64) }
    }

    @inline(__always)
    public mutating func remove(_ pitch: Int) {
        guard (0...127).contains(pitch) else { return }
        if pitch < 64 { low &= ~(1 << UInt64(pitch)) } else { high &= ~(1 << UInt64(pitch - 64)) }
    }

    public var isEmpty: Bool { low == 0 && high == 0 }
    public var count: Int { low.nonzeroBitCount + high.nonzeroBitCount }

    public func union(_ other: PitchSet) -> PitchSet {
        var s = self; s.low |= other.low; s.high |= other.high; return s
    }

    public func intersection(_ other: PitchSet) -> PitchSet {
        var s = self; s.low &= other.low; s.high &= other.high; return s
    }

    public func subtracting(_ other: PitchSet) -> PitchSet {
        var s = self; s.low &= ~other.low; s.high &= ~other.high; return s
    }

    public func isSuperset(of other: PitchSet) -> Bool { other.subtracting(self).isEmpty }

    /// The pitches, lowest first. Allocates: for display, not realtime code.
    public var sorted: [Int] { (0...127).filter { self.contains($0) } }

    /// As a Swift set. Allocates: for display, not realtime code.
    public var asSet: Set<Int> { Set(sorted) }
}
