import XCTest
@testable import PianoGraderCore

final class SPSCRingTests: XCTestCase {
    func testPushPopInOrderAndFull() {
        let ring = SPSCRing<Int>.allocate(minimumCapacity: 3, blank: 0)   // rounds up to 4
        defer { ring.deallocate() }
        XCTAssertEqual(ring.capacity, 4)
        for i in 1...4 { XCTAssertTrue(ring.push(i)) }
        XCTAssertFalse(ring.push(5))
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(ring.pop(), 1)
        XCTAssertTrue(ring.push(5))
        var out = [Int](repeating: 0, count: 10)
        let n = out.withUnsafeMutableBufferPointer { ring.pop(into: $0) }
        XCTAssertEqual(Array(out.prefix(n)), [2, 3, 4, 5])
        XCTAssertNil(ring.pop())
    }

    func testStridedPushPicksOneChannel() {
        let ring = SPSCRing<Float>.allocate(minimumCapacity: 8, blank: 0)
        defer { ring.deallocate() }
        let interleaved: [Float] = [1, -1, 2, -2, 3, -3]
        let written = interleaved.withUnsafeBufferPointer { ring.push(from: $0.baseAddress!, count: 3, stride: 2) }
        XCTAssertEqual(written, 3)
        var out = [Float](repeating: 0, count: 3)
        _ = out.withUnsafeMutableBufferPointer { ring.pop(into: $0) }
        XCTAssertEqual(out, [1, 2, 3])
    }

    func testConcurrentProducerAndConsumerKeepEveryValueInOrder() {
        let ring = SPSCRing<Int>.allocate(minimumCapacity: 64, blank: 0)
        defer { ring.deallocate() }
        let total = 200_000
        let producer = Thread {
            var i = 0
            while i < total { if ring.push(i) { i += 1 } }
        }
        producer.start()
        var expected = 0
        while expected < total {
            if let v = ring.pop() {
                XCTAssertEqual(v, expected)
                expected += 1
            }
        }
    }
}

final class RealtimeEventQueueTests: XCTestCase {
    func testDeliversPostedValuesInOrder() {
        let done = expectation(description: "all delivered")
        var received: [Int] = []
        let lock = NSLock()
        let queue = RealtimeEventQueue<Int>(capacity: 1024, blank: 0, name: "test") { batch in
            lock.lock()
            received += batch
            let finished = received.count == 500
            lock.unlock()
            if finished { done.fulfill() }
        }
        let poster = queue.poster
        for i in 0..<500 { poster.post(i) }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(received, Array(0..<500))
        XCTAssertEqual(queue.droppedCount, 0)
    }
}
