import Foundation
import ReactiveSwift
import ReactorCore
import Result
import XCTest

class Register: ReactorCore<Register.Event, Register.State, Never> {
    enum Event {
        case inc
        case dec
    }

    struct State: Equatable {
        let register: Int
    }

    override func react(
        to state: State
    ) -> Reaction<Event, State, Never> {
        return buildReaction { when in
            when.received { event in
                switch event {
                case .inc: return .enterState(State(register: state.register + 1))
                case .dec: return .enterState(State(register: state.register - 1))
                }
            }
        }
    }
}

private class SimpleRegister {
    enum Event {
        case inc
        case dec
    }

    struct State {
        let register: Int
    }

    func next(state: State, event: Event) -> State {
        switch event {
        case .inc: return State(register: state.register + 1)
        case .dec: return State(register: state.register - 1)
        }
    }

    func process(initial: State, events: [Event]) -> State {
        let state = MutableProperty(initial)
        state <~ SignalProducer(events)
            .scan(initial) { state, event in
                self.next(state: state, event: event)
            }
        return state.value
    }
}

class PeformanceTests: XCTestCase {
    private enum Consts {
        static let count = 5000
    }

    // FIXME: Get in sub 100ms league on my mac
    func testRegister() {
        measure {
            let register = Register(initialState: .init(register: 0))

            DispatchQueue.global().async {
                for _ in 1 ... Consts.count {
                    register.send(event: .inc)
                }
            }

            register.launch()

            DispatchQueue.global().async {
                for _ in 1 ... 2 * Consts.count {
                    register.send(event: .dec)
                }
            }

            register.send(event: .dec)

            let exp = expectation(description: "Process finished")
            register.state.producer
                .map { $0.unwrapped }
                .filter { $0.register == -(Consts.count + 1) }
                .take(first: 1)
                .on(completed: {
                    exp.fulfill()
                })
                .start()

            waitForExpectations(timeout: 20)
        }
    }

    func testSimpleRegister() {
        let events =
            Array(1 ... Consts.count).map { _ in SimpleRegister.Event.inc } +
            Array(1 ... 2 * Consts.count).map { _ in SimpleRegister.Event.dec } +
            [SimpleRegister.Event.dec]

        let register = SimpleRegister()

        measure {
            let result = register.process(initial: .init(register: 0), events: events)

            XCTAssert(result.register == -(Consts.count + 1))
        }
    }

    func testAggregation() {
        measure {
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

            for child in children {
                child.send(syncEvent: .inc)
            }
            parent.send(syncEvent: .inc)
            let state = parent.unwrappedState.value
            XCTAssert(state.total == Consts.count * 2 + (children.count + 1))
        }
    }
}
