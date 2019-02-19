import XCTest
@testable import Workflows

class ValueQueueTests: XCTestCase {

    func testEventsBeforeRequestQueue() {
        let queue = ValueQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        
        XCTAssert(queue.nextValue().single()!.value! == 1)
        XCTAssert(queue.nextValue().single()!.value! == 2)
    }
    
    func testEventAfterRequest() {
        let queue = ValueQueue<Int>()
        
        DispatchQueue(label: "Test").async {
            queue.enqueue(1)
            DispatchQueue(label: "Test2").async {
                queue.enqueue(2)
            }
        }

        XCTAssert(queue.nextValue().single()!.value! == 1)
        XCTAssert(queue.nextValue().single()!.value! == 2)
    }
    
    // FIXME: if queues are full, interrupt won't come through it
    // On my mac queues count happen to be 68
    func testContendedQueue() {
        let count = 50
        
        let queue = ValueQueue<Int>()
        
        let dQueue = DispatchQueue(label: "Test Queue")
        for i in 1...count {
            dQueue.async {
                queue.enqueue(i)
            }
        }
        
        let concurrent = DispatchQueue(label: "Concurrent", attributes: .concurrent)
        let dispatchGroup = DispatchGroup()
        for _ in 1..<count {
            concurrent.async(group: dispatchGroup) {
                _ = queue.nextValue().logEvents().take(first: 1).single()
            }
        }
        
        dispatchGroup.wait()
        
        XCTAssert(queue.nextValue().take(first: 1).single()!.value! == count)
    }
    
    func testInsequentialDisposal() {
        let queue = ValueQueue<Int>()
        
        var recievedValue: Int? = nil
        
        let next1 = queue.nextValue()
            .on { value in
                print("first recieved \(value)")
                recievedValue = value
            }
            .start()
        let next2 = queue.nextValue().start()
        let next3 = queue.nextValue().start()
        
        queue.enqueue(1)
        next3.dispose()
        
        queue.enqueue(2)
        next2.dispose()
        
        queue.enqueue(3)
        // This must deadlock, because next1 is still alive
        let got = queue.nextValue().take(first: 1).single()!.value!
        XCTAssert(got == 3)
        print(got)
        
        next1.dispose()
        XCTAssert(recievedValue == 1)
    }
}
