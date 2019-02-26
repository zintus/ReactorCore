import XCTest

class SyncEventTests: XCTestCase {
    func testSyncEvent() {
        let register = Register(initialState: .init(register: 0))
        register.launch()
        register.send(syncEvent: .inc)

        XCTAssert(register.unwrappedState.value.register == 1)
    }
}
