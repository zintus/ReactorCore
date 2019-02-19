import Foundation
import ReactiveSwift
import Result

protocol Reactor: class, Workflow, SingleLike {
    func react(
        to state: State,
        eventSource: SignalProducer<Event, NoError>
    ) -> Reaction<State, Value>

    func buildReaction(_ builderBlock: (ReactionBuilder<State, Value>) -> Void) -> Reaction<State, Value>
    func buildEventReaction(_ event: SignalProducer<Event, NoError>,
                            _ mapper: @escaping (Event) -> StateTransition<State, Value>?) -> Reaction<State, Value>
}

private let reactorLogLock = Atomic(())

class BaseReactor<E, S, R>: Reactor {
    typealias Event = E
    typealias State = S
    typealias Value = R

    init(initialState: S) {
        mutableState = MutableProperty(CompleteState.running(initialState))
        state = Property(capturing: mutableState)
    }

    private var launched: Bool = false
    private let mutableState: MutableProperty<CompleteState>
    let state: Property<CompleteState>

    func react(
        to _: S,
        eventSource _: SignalProducer<E, NoError>
    ) -> Reaction<S, R> {
        fatalError()
    }

    func launch() {
        if !launched {
            launched = true

            switch mutableState.value {
            case let .running(firstState):
                mutableState <~ buildState(firstState, eventSource: eventsQueue)
            case .finished:
                fatalError("Trying to start already finished workflow")
            }
        } else {
            fatalError()
        }
    }

    private let eventsQueue = ValueQueue<E>()

    func send(event: E) {
        eventsQueue.enqueue(event)
    }

    private func buildState(_ initialState: State, eventSource: ValueQueue<E>) -> Property<WorkflowState<S, R>> {
        typealias CompleteState = WorkflowState<S, R>

        let continueStateStream = { [weak self] (_ prev: CompleteState) -> SignalProducer<CompleteState, NoError> in
            guard let self = self else { return .empty }

            switch prev {
            case .finished:
                return .empty

            case let .running(current):
                var usedEvent: E?
                
                let nextValue = eventSource.nextValue()
                let eventWithLogs = nextValue.value.producer
                    .skipNil()
                    .on(interrupted: {
                        nextValue.cancel()
                    }, value: { _ in
                        nextValue.consume()
                    })
                    .on(value: { consumedEvent in
                        usedEvent = consumedEvent
                    })

                return self.react(to: current, eventSource: eventWithLogs)
                    .signalProducer
                    .logEvents(identifier: "continueStateStream \(type(of: self))")
                    .take(first: 1) // This is crucial
                    .map { [weak self] transition in
                        guard let self = self else { return transition.nextState }

                        if Debug.printStateTransitions {
                            // Lazy and want to keep logs consistent
                            reactorLogLock.modify { _ in
                                print("\(self)------------")
                                print("from: \(prev)")
                                if let usedEvent = usedEvent {
                                    print("+ \(usedEvent)")
                                }
                                print("to: \(transition.nextState)")
                                print("------------")
                            }
                        }
                        return transition.nextState
                    }
            }
        }

        let result: SignalProducer<CompleteState, NoError> = SignalProducer { observer, lifetime in
            DispatchQueue.global().async {
                var currentState = CompleteState.running(initialState)

                while let nextState = continueStateStream(currentState)
                    .take(during: lifetime)
                    .single()?.value {
                    observer.send(value: nextState)
                    currentState = nextState
                }

                observer.sendCompleted()
            }
        }

        let first = CompleteState.running(initialState)
        return Property(initial: first, then: result)
    }

    // MARK: - Build Reactions

    private let scheduler = QueueScheduler(name: "BaseReactor.scheduler")

    func buildReaction(_ builderBlock: (ReactionBuilder<State, Value>) -> Void) -> Reaction<State, Value> {
        return Reaction(scheduler: scheduler, builderBlock)
    }

    func buildEventReaction(_ event: SignalProducer<Event, NoError>,
                            _ mapper: @escaping (Event) -> StateTransition<State, Value>?) -> Reaction<State, Value> {
        return EventReaction(scheduler: scheduler, event, mapper)
    }
}

class ValueQueue<Value> {
    init() {}

    typealias Producer = SignalProducer<Value, NoError>
    typealias Waiter = (observer: Producer.ProducedSignal.Observer, lifetime: Lifetime)
    typealias State = (values: [Value], waiters: [Waiter], lockedFirstEntry: Bool)
    private let state = Atomic<State>(([], [], false))

    private func lockFirstEvent(state: inout State) {
        guard !state.lockedFirstEntry else { return }

        state.waiters = state.waiters.filter { !$0.lifetime.hasEnded }

        if let first = state.values.first,
            let waiter = state.waiters.first {
            waiter.observer.send(value: first)

            state.lockedFirstEntry = true
            print("locked waiter length \(state.waiters.count)")

            print(ObjectIdentifier(waiter.observer))
        }
    }
    
    class NextValue {
        typealias Observer = SignalProducer<Value, NoError>.ProducedSignal.Observer
        private weak var queue: ValueQueue<Value>?
        private let observer: Observer
        let value: Property<Value?>
        
        func consume() {
            DispatchQueue.global().async {
                self.queue?.consume(self.observer)
            }
        }
        
        func cancel() {
            DispatchQueue.global().async {
                self.queue?.cancel(self.observer)
            }
        }
        
        init(property: Property<Value?>, observer: Observer, queue: ValueQueue<Value>) {
            self.value = property
            self.queue = queue
            self.observer = observer
        }
    }
    
    private func consume(_ observer: SignalProducer<Value, NoError>.ProducedSignal.Observer) {
        self.state.modify { (state: inout State) in
            guard let index = state.waiters.firstIndex(where: { $0.observer === observer }) else {
                return
            }
            
            if index == 0 {
                if state.lockedFirstEntry {
                    state.values.remove(at: 0)
                    state.lockedFirstEntry = false
                    state.waiters.remove(at: 0)
                    print("unlocked waiter length \(state.waiters.count)")
                }
                
                self.lockFirstEvent(state: &state)
            } else {
                fatalError("Trying to consume without sending an event!")
            }
        }
    }
    
    private func cancel(_ observer: SignalProducer<Value, NoError>.ProducedSignal.Observer) {
        self.state.modify { (state: inout State) in
            guard let index = state.waiters.firstIndex(where: { $0.observer === observer }) else {
                return
            }
            
            state.waiters.remove(at: index)
            if index == 0 {
                state.lockedFirstEntry = false
                self.lockFirstEvent(state: &state)
            }
        }
    }

    func nextValue() -> NextValue {
        var currentObserver: SignalProducer<Value, NoError>.ProducedSignal.Observer?
        
        let producer = SignalProducer<Value, NoError> { observer, lifetime in
            currentObserver = observer
            
            self.state.modify { (state: inout State) in
                print("await")
                state.waiters.append((observer, lifetime))
                print(state)
                
                self.lockFirstEvent(state: &state)
            }
        }
        
        return NextValue(property: Property(initial: nil, then: producer),
                         observer: currentObserver!,
                         queue: self)
    }

    func enqueue(_ value: Value) {
        state.modify { (state: inout State) in
            print("append")
            state.values.append(value)

            lockFirstEvent(state: &state)
        }
    }
}

// Only purpose of this is sugar
private extension StateTransition {
    var nextState: WorkflowState<State, Value> {
        switch self {
        case let .enterState(state): return .running(state)
        case let .finishWith(value): return .finished(value)
        }
    }
}

private struct Debug {
    static let printStateTransitions = true
}
