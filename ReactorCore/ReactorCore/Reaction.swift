import Foundation
import ReactiveSwift
import Result

// Pure syntactic sugar
public enum StateTransition<State, FinalState> {
    case enterState(State)
    case finishWith(FinalState)
}

public class Reaction<Event, State, FinalState> {
    let signalProducer: SignalProducer<StateTransition<State, FinalState>, NoError>

    public init(
        scheduler: QueueScheduler,
        eventQueue: ValueQueue<(Event, DispatchSemaphore?)>,
        _ builderBlock: (ReactionBuilder<Event, State, FinalState>) -> Void
    ) {
        let builder = ReactionBuilder<Event, State, FinalState>(scheduler, eventQueue: eventQueue)
        builderBlock(builder)
        signalProducer = SignalProducer { observer, lifetime in
            builder.futureState.onValue = { value in
                observer.send(value: value.0)
                value.1?.signal()

                DispatchQueue.global().async {
                    observer.sendCompleted()
                }
            }

            lifetime.observeEnded {
                withExtendedLifetime(builder) {}
            }
        }
    }

    public init(_ signalProducer: SignalProducer<StateTransition<State, FinalState>, NoError>) {
        self.signalProducer = signalProducer
    }

    public init(value: StateTransition<State, FinalState>) {
        signalProducer = SignalProducer(value: value)
    }
}
