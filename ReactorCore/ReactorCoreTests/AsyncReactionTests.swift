import Foundation
import ReactiveSwift
import ReactorCore
import Result
import XCTest

private class Minimal: ReactorCore<Minimal.Event, Minimal.State, Never> {
    enum Event {}

    struct State {}

    override func react(to _: State) -> Reaction<Event, State, Never> {
        return buildReaction { _ in }
    }
}

private class FastAndSlow: ReactorCore<FastAndSlow.Event, FastAndSlow.State, Never> {
    enum Event {
        case slowEvent
        case minimalState
    }

    struct State {
        let event: Event?
    }

    override init(initialState: State, scheduler: QueueScheduler = QueueScheduler(name: "QueueScheduler.FastAndSlow")) {
        otherSource = WorkflowHandle(Minimal(initialState: .init()), scheduler: scheduler)
        super.init(initialState: initialState, scheduler: scheduler)
    }

    private let otherSource: WorkflowHandle<Minimal>

    override func react(
        to state: State
    ) -> Reaction<Event, State, Never> {
        guard state.event == nil else {
            return buildReaction { _ in }
        }

        return buildReaction { (when: ReactionBuilder<Event, State, Never>) in
            // This option wins
            when.receivedFlatMap { event in
                SignalProducer(value: .enterState(State(event: event)))
                    .delay(1, on: QueueScheduler())
            }

            when.workflowUpdated(otherSource) { _ in
                .enterState(State(event: Event.minimalState))
            }
        }
    }
}

class FastAndSlowTests: XCTestCase {
    func testFastAndSlow() {
        let core = FastAndSlow(initialState: .init(event: nil))
        core.send(event: .slowEvent)
        core.launch()

        let exp = expectation(description: "Process finished")
        core.state.producer
            .map { $0.unwrapped }
            .filter { $0.event != nil }
            .logEvents()
            .on { state in
                if state.event == .slowEvent {
                    exp.fulfill()
                } else {
                    XCTFail()
                }
            }
            .start()

        waitForExpectations(timeout: 5)
    }
}
