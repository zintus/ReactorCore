import Foundation
import ReactiveSwift
import Result
import XCTest
import Dispatch
@testable import Workflows

private class Register: ReactorCore<Register.Event, Register.State, Never> {
    enum Event {
        case inc
        case dec
    }

    struct State {
        let register: Int
    }

    override func react(
            to state: State,
            eventSource: SignalProducer<Event, NoError>
    ) -> Reaction<State, Never> {
        return buildReaction { when in
            when.receivedEvent(eventSource) { event in
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
        var state = initial
        for event in events {
            state = next(state: state, event: event)
        }
        return state
    }
}

class RegisterTests: XCTestCase {
    private enum Consts {
        static let count = 5_000
    }
    
    // FIXME: Get in sub 100ms league on my mac
    func testRegister() {
        measure {
            let register = Register(initialState: .init(register: 0))

            DispatchQueue.global().async {
                for _ in 1...Consts.count {
                    register.send(event: .inc)
                }
            }

            register.launch()

            DispatchQueue.global().async {
                for _ in 1...2 * Consts.count {
                    register.send(event: .dec)
                }
            }

            register.send(event: .dec)

            let exp = expectation(description: "Process finished")
            register.state.producer
                    .map { $0.unwrapped }
                    .filter { $0.register == -(Consts.count+1) }
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
            Array(1...Consts.count).map { _ in SimpleRegister.Event.inc } +
            Array(1...2 * Consts.count).map { _ in SimpleRegister.Event.dec } +
            [SimpleRegister.Event.dec]
        
        let register = SimpleRegister()
        
        measure {
            let result = register.process(initial: .init(register: 0), events: events)
            
            XCTAssert(result.register == -(Consts.count + 1))
        }
    }
}
