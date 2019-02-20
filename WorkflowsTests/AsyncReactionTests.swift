import Foundation
import ReactiveSwift
import Result
@testable import Workflows
import XCTest

private class Minimal: ReactorCore<Minimal.Event, Minimal.State, Never> {
    enum Event {

    }

    struct State {

    }

    override func react(to: State, eventSource: SignalProducer<Event, NoError>) -> Reaction<State, Never> {
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

    private let otherSource = WorkflowHandle(Minimal(initialState: .init()))

    override func react(
        to state: State,
        eventSource: SignalProducer<Event, NoError>
    ) -> Reaction<State, Never> {
        guard state.event == nil else {
            return buildReaction { _ in }
        }

        return buildReaction { when in
            when.receivedEvent(eventSource.delay(1, on: QueueScheduler())) { event in
                return .enterState(State(event: event))
            }

            when.workflowUpdated(otherSource) { minimal in
                return .enterState(State(event: .minimalState))
            }
        }
    }
}

class FastAndSlowTests: XCTestCase {
    // FIXME:
    // When next state processing takes time, first transition which started executing must win
    // effectively ignoring other transitions (workflow update in our case)
    func testFastAndSlow() {
        let core = FastAndSlow(initialState: .init(event: nil))
        core.send(event: .slowEvent)
        core.launch()

        let exp = expectation(description: "Process finished")
        core.state.producer
            .map { $0.unwrapped }
            .logEvents()
            .filter { $0.event == .slowEvent }
            .take(first: 1)
            .on(completed: {
                exp.fulfill()
            })
            .start()

        waitForExpectations(timeout: 5)
    }
}