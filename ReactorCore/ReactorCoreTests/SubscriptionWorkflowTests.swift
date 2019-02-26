import ReactiveSwift
import ReactorCore
import Result
import XCTest

class SubscriptionWorkflowTests: XCTestCase {
    func testSubscriptionWorkflowCompletion() {
        let producer = SignalProducer<String, NoError>.empty
        let workflow = producer.asWorkflow()
        workflow.launch()

        expect(workflow.state, toBeEqual: .finished(nil))
        waitForExpectations(timeout: 1)
    }

    func testSubscriptionWorkflowFinalValue() {
        let producer = SignalProducer<String, NoError>(value: "123")
        let workflow = producer.asWorkflow()
        workflow.launch()

        expect(workflow.state, toBeEqual: .finished("123"))
        waitForExpectations(timeout: 1)
    }

    func testSubscriptionWorkflowLiveValues() {
        let (signal, observer) = Signal<String, NoError>.pipe()
        let workflow = signal.producer.asWorkflow()
        workflow.launch()

        observer.send(value: "123")
        expect(workflow.state, toBeEqual: .running("123"))
        waitForExpectations(timeout: 1)

        observer.send(value: "321")
        expect(workflow.state, toBeEqual: .running("321"))
        waitForExpectations(timeout: 1)

        observer.send(value: "111")
        observer.sendCompleted()
        expect(workflow.state, toBeEqual: .finished("111"))
        waitForExpectations(timeout: 1)
    }
}
