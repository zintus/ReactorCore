import Foundation
import ReactiveSwift
import Result

// Pure syntactic sugar
enum StateTransition<State, Value> {
    case enterState(State)
    case finishWith(Value)
}

class Reaction<Event, State, Value> {
    let signalProducer: SignalProducer<StateTransition<State, Value>, NoError>

    init(
        scheduler: QueueScheduler,
        eventQueue: ValueQueue<Event>,
        _ builderBlock: (ReactionBuilder<Event, State, Value>) -> Void
    ) {
        let builder = ReactionBuilder<Event, State, Value>(scheduler, eventQueue: eventQueue)
        builderBlock(builder)
        signalProducer = SignalProducer { observer, lifetime in
            builder.futureState.onValue = { value in
                observer.send(value: value)
                
                DispatchQueue.global().async {
                    observer.sendCompleted()
                }
            }
            
            lifetime.observeEnded {
                withExtendedLifetime(builder) { }
            }
        }
    }

    init(_ signalProducer: SignalProducer<StateTransition<State, Value>, NoError>) {
        self.signalProducer = signalProducer
    }

    init(value: StateTransition<State, Value>) {
        signalProducer = SignalProducer(value: value)
    }
}
