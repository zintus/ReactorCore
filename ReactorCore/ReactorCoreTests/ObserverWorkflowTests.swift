import ReactiveSwift
import ReactorCore
import Result
import XCTest

class ObserverWorkflowTests: XCTestCase {
    func testSubscriptionWorkflowLiveValues() {
        let (signal, observer) = Signal<String, NoError>.pipe()
        let property = Property(initial: "123", then: signal.producer)
        let workflow = property.asWorkflow()

        expect(workflow.unwrappedState, toBeEqual: "123")
        waitForExpectations(timeout: 1)

        observer.send(value: "321")
        expect(workflow.unwrappedState, toBeEqual: "321")
        waitForExpectations(timeout: 1)

        observer.send(value: "111")
        observer.sendCompleted()
        expect(workflow.unwrappedState, toBeEqual: "111")
        waitForExpectations(timeout: 1)
    }
}
