import Foundation
import ReactiveSwift
import Result
@testable import Workflows
import XCTest

private class Minimal: ReactorCore<Minimal.Event, Minimal.State, Never> {
    enum Event {}

    struct State {}

    override func react(to _: State) -> Reaction<State, Never> {
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
        to state: State
    ) -> Reaction<State, Never> {
        guard state.event == nil else {
            return buildReaction { _ in }
        }

        return buildReaction { when in
            when.received { event in
                .enterState(State(event: event))
            }

            when.workflowUpdated(otherSource) { _ in
                .enterState(State(event: .minimalState))
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
