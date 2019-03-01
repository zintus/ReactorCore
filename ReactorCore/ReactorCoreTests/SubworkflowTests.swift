import Foundation
import ReactiveSwift
@testable import ReactorCore
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
        let scheduler = QueueScheduler(name: "Aggregator.scheduler")
        super.init(initialState: .init(
            counter: 0,
            children: children.map { WorkflowHandle.makeAndLaunch($0, scheduler: scheduler) }
        ),
                   scheduler: scheduler)
    }

    override func react(to state: State) -> Reaction<Event, State, Never> {
        return buildReaction { when in
            for (index, child) in state.children.enumerated() {
                when.workflowUpdated(child) { handle in
                    var children = state.children
                    children[index] = handle
                    return .enterState(state.with(
                        children: children
                    ))
                }
            }

            when.received { event in
                switch event {
                case .inc: return .enterState(state.with(counter: state.counter + 1))
                }
            }
        }
    }
}

class ReactiveAggregator: ReactorCore<ReactiveAggregator.Event, ReactiveAggregator.State, Never> {
    enum Event {
        case inc
    }

    struct State {
        let counter: Int

        let children: [WorkflowHandle<ReactiveAggregator>]

        var total: Int {
            return counter + children.reduce(into: 0) { $0 = $0 + $1.state.unwrapped.counter }
        }

        func with(counter: Int) -> State {
            return State(counter: counter, children: children)
        }

        func with(children: [WorkflowHandle<ReactiveAggregator>]) -> State {
            return State(counter: counter, children: children)
        }
    }

    init(_ children: [ReactiveAggregator]) {
        let scheduler = QueueScheduler(name: "Aggregator.scheduler")
        super.init(initialState: .init(
            counter: 0,
            children: children.map { WorkflowHandle.makeAndLaunch($0, scheduler: scheduler) }
        ),
                   scheduler: scheduler)
    }

    override func react(to state: State) -> Reaction<Event, State, Never> {
        return buildReaction { when in
            for (index, child) in state.children.enumerated() {
                when.workflowUpdatedFlatMap(child) { handle in
                    var children = state.children
                    children[index] = handle
                    return SignalProducer(value: .enterState(state.with(
                        children: children
                    )))
                        .observe(on: QueueScheduler())
                }
            }

            when.receivedFlatMap { event in
                switch event {
                case .inc: return SignalProducer(value: .enterState(state.with(counter: state.counter + 1)))
                    .observe(on: QueueScheduler())
                }
            }
        }
    }
}

class SubworkflowTests: XCTestCase {
    private enum Consts {
        static let count = 1000
    }

    func testAggregation() {
        let children = Array(1 ... 10).map { _ in Aggregator([]) }

        let parent = Aggregator(children)

        let tasks = DispatchGroup()
        DispatchQueue.global().async(group: tasks) {
            for _ in 1 ... Consts.count {
                parent.send(event: .inc)
            }
        }

        parent.launch()

        DispatchQueue.global().async(group: tasks) {
            for _ in 1 ... Consts.count {
                children.randomElement()!.send(event: .inc)
            }
        }

        tasks.wait()

        for child in children {
            child.send(syncEvent: .inc)
        }
        parent.send(syncEvent: .inc)
        let state = parent.unwrappedState.value
        XCTAssert(state.total == Consts.count * 2 + (children.count + 1))
    }

    func testReactiveAggregation() {
        let children = Array(1 ... 10).map { _ in ReactiveAggregator([]) }

        let parent = ReactiveAggregator(children)

        let tasks = DispatchGroup()
        DispatchQueue.global().async(group: tasks) {
            for _ in 1 ... Consts.count {
                parent.send(event: .inc)
            }
        }

        parent.launch()

        DispatchQueue.global().async(group: tasks) {
            for _ in 1 ... Consts.count {
                children.randomElement()!.send(event: .inc)
            }
        }

        tasks.wait()

        for child in children {
            child.send(syncEvent: .inc)
        }
        parent.send(syncEvent: .inc)
        let state = parent.unwrappedState.value
        XCTAssert(state.total == Consts.count * 2 + (children.count + 1))
    }
}
