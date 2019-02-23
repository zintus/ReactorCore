@testable import Workflows
import XCTest

private extension ValueQueue {
    var getUnsafe: Value {
        let nextValue2 = nextValue()
        let result = nextValue2.producer
            .on { _ in
                nextValue2.consume()
            }
            .take(first: 1)
            .single()!.value!
        return result
    }
}

class ValueQueueTests: XCTestCase {
    func testEventsBeforeRequestQueue() {
        let queue = ValueQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)

        XCTAssert(queue.getUnsafe == 1)
        XCTAssert(queue.getUnsafe == 2)
    }

    func testEventAfterRequest() {
        let queue = ValueQueue<Int>()

        DispatchQueue(label: "Test").async {
            queue.enqueue(1)
            DispatchQueue(label: "Test2").async {
                queue.enqueue(2)
            }
        }

        XCTAssert(queue.getUnsafe == 1)
        XCTAssert(queue.getUnsafe == 2)
    }

    // FIXME: if queues are full, interrupt won't come through it
    // On my mac queues count happen to be 68
    func testContendedQueue() {
        let count = 50

        let queue = ValueQueue<Int>()

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
                _ = queue.getUnsafe
            }
        }

        dispatchGroup.wait()

        let value = queue.getUnsafe
        print(value)
        XCTAssert(value == count)
    }

    func skipped_testInsequentialDisposal() {
        let queue = ValueQueue<Int>()

        var recievedValue: Int?

        let next1 = queue.nextValue().producer
            .on { value in
                print("first recieved \(value)")
                recievedValue = value
            }
            .start()
        let next2 = queue.nextValue().producer.start()
        let next3 = queue.nextValue().producer.start()

        queue.enqueue(1)
        next3.dispose()

        queue.enqueue(2)
        next2.dispose()

        queue.enqueue(3)
        // This must deadlock, because next1 is still alive
        let got = queue.getUnsafe
        XCTAssert(got == 3)
        print(got)

        next1.dispose()
        XCTAssert(recievedValue == 1)
    }
}
