@testable import Workflows
import XCTest
import ReactiveSwift

private extension ValueQueue {
    var getUnsafe: Value {
        let nextValue2 = dequeue()
        var result: Value!
        nextValue2.onValue = { newValue in
            result = newValue
        }
        return result
    }
}

class ValueQueueTests: XCTestCase {
    func testEventsBeforeRequestQueue() {
        let scheduler = QueueScheduler(name: "Test")
        let queue = ValueQueue<Int>(scheduler)
        queue.enqueue(1)
        queue.enqueue(2)

        scheduler.queue.sync {
            XCTAssert(queue.getUnsafe == 1)
            XCTAssert(queue.getUnsafe == 2)
        }
    }

    func testEventAfterRequest() {
        let scheduler = QueueScheduler(name: "Test")
        let queue = ValueQueue<Int>(scheduler)

        let dispatchGroup = DispatchGroup()
        DispatchQueue(label: "Test").async(group: dispatchGroup) {
            queue.enqueue(1)
            DispatchQueue(label: "Test2").async(group: dispatchGroup) {
                queue.enqueue(2)
            }
        }
        dispatchGroup.wait()

        scheduler.queue.sync {
            XCTAssert(queue.getUnsafe == 1)
            XCTAssert(queue.getUnsafe == 2)
        }
    }

    func testContendedQueue() {
        let scheduler = QueueScheduler(name: "Test")
        let count = 10000

        let queue = ValueQueue<Int>(scheduler)

        let dQueue = DispatchQueue(label: "Test Queue")
        for i in 1 ... count {
            dQueue.async {
                queue.enqueue(i)
            }
        }

        let concurrent = DispatchQueue(label: "Concurrent", attributes: .concurrent)
        let dispatchGroup = DispatchGroup()
        for _ in 1 ..< count {
            concurrent.async(group: dispatchGroup) {
                scheduler.queue.sync { _ = queue.getUnsafe }
            }
        }

        dispatchGroup.wait()

        let value = scheduler.queue.sync { queue.getUnsafe }
        print(value)
        XCTAssert(value == count)
    }
}
