import Foundation
import ReactiveSwift
import XCTest

extension XCTestCase {
    @discardableResult
    func expect<T: SignalProducerConvertible>(
        _ producer: T,
        toBeEqual expected: T.Value
    ) -> XCTestExpectation where T.Value: Equatable {
        let exp = expectation(description: "Expect producer to be equal to value")
        producer.producer
            .filter { $0 == expected }
            .take(first: 1)
            .on(completed: {
                exp.fulfill()
            }).start()

        return exp
    }
}

class DeallocationTests: XCTestCase {
    func testDeallocation() {
        weak var registerWeak: Register?

        _ = {
            let register = Register(initialState: .init(register: 0))
            register.send(event: .inc)
            register.launch()
            registerWeak = register
        }()

        XCTAssert(registerWeak == nil)
    }
}
