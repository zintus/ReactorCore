import Foundation
import XCTest
@testable import Workflows

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
