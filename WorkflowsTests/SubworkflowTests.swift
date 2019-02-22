import Foundation
@testable import Workflows
import XCTest

class Aggregator: ReactorCore<Aggregator.Event, Aggregator.State, Never> {
    enum Event {
        case inc
    }

    struct State {
        let counter: Int

        let children: [WorkflowHandle<Aggregator>]

        var total: Int {
            return counter + children.reduce(into: 0) { $0 = $0 + $1.state.unwrapped.counter }
        }

        func with(counter: Int) -> State {
            return State(counter: counter, children: children)
        }

        func with(children: [WorkflowHandle<Aggregator>]) -> State {
            return State(counter: counter, children: children)
        }
    }

    init(_ children: [Aggregator]) {
        super.init(initialState: .init(counter: 0, children: children.map { WorkflowHandle($0) }))
    }

    override func react(to state: State) -> Reaction<State, Never> {
        return buildReaction { when in
            when.received { event in
                switch event {
                case .inc: return .enterState(state.with(counter: state.counter + 1))
                }
            }

            for (index, child) in state.children.enumerated() {
                when.workflowUpdated(child) { handle in
                    var children = state.children
                    children[index] = handle
                    return .enterState(state.with(
                        children: children
                    ))
                }
            }
        }
    }
}

class SubworkflowTests: XCTestCase {
    private enum Consts {
        static let count = 500
    }

    func testAggregation() {
        let children = Array(1 ... 10).map { _ in Aggregator([]) }

        let parent = Aggregator(children)

        DispatchQueue.global().async {
            for _ in 1 ... Consts.count {
                parent.send(event: .inc)
            }
        }

        parent.launch()

        DispatchQueue.global().async {
            for _ in 1 ... Consts.count {
                children.randomElement()!.send(event: .inc)
            }
        }

        let exp = expectation(description: "finished")
        parent.unwrappedState
            .producer
            .filter { state in
                state.total == Consts.count * 2
            }
            .take(first: 1)
            .on(completed: {
                exp.fulfill()
            })
            .start()

        waitForExpectations(timeout: 5)
    }
}
