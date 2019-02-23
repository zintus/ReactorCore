import Foundation
import ReactiveSwift
import Result

protocol Reactor: class, Workflow, SingleLike {
    func react(
        to state: State
    ) -> Reaction<State, Value>

    func buildReaction(
        _ builderBlock: (ReactionBuilder<Event, State, Value>) -> Void
    ) -> Reaction<State, Value>
    func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, Value>?
    ) -> Reaction<State, Value>
}

class ReactorCore<E, S, R>: Reactor {
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
        to _: S
    ) -> Reaction<S, R> {
        fatalError()
    }

    func launch() {
        if !launched {
            launched = true

            switch mutableState.value {
            case let .running(firstState):
                mutableState <~ buildState(firstState)
            case .finished:
                fatalError("Trying to start already finished workflow")
            }
        } else {
            fatalError()
        }
    }

    private let eventQueue = ValueQueue<E>()

    func send(event: E) {
        eventQueue.enqueue(event)
    }

    private func buildState(_ initialState: State) -> Property<WorkflowState<S, R>> {
        typealias CompleteState = WorkflowState<S, R>

        let continueStateStream = { [weak self] (_ prev: CompleteState) -> SignalProducer<CompleteState, NoError> in
            guard let self = self else { return .empty }

            switch prev {
            case .finished:
                return .empty

            case let .running(current):
                return self.react(to: current)
                    .signalProducer
                    .take(first: 1) // This is crucial
                    .map { $0.nextState }
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

    func buildReaction(
        _ builderBlock: (ReactionBuilder<Event, State, Value>) -> Void
    ) -> Reaction<State, Value> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue, builderBlock)
    }

    func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, Value>?
    ) -> Reaction<State, Value> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue) { when in
            when.received(mapper)
        }
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

        if let first = state.values.first,
            let waiter = state.waiters.first {
            waiter.observer.send(value: first)

            state.lockedFirstEntry = true
        }
    }

    class NextValue {
        typealias Producer = SignalProducer<Value, NoError>
        typealias Observer = Producer.ProducedSignal.Observer
        private weak var queue: ValueQueue<Value>?
        private var observer: Observer?
        private(set) var producer: Producer!

        func consume() {
            DispatchQueue.global().async {
                self.queue?.consume(self.observer!)
            }
        }

        func cancel() {
            DispatchQueue.global().async {
                self.queue?.cancel(self.observer!)
            }
        }
        
        init(queue: ValueQueue<Value>, _ startHandler: @escaping (Producer.ProducedSignal.Observer, Lifetime) -> Void) {
            self.queue = queue
            
            producer = Producer { [weak self] observer, lifetime in
                guard let self = self else { return }
                
                self.observer = observer
                startHandler(observer, lifetime)
            }
        }
    }

    private func consume(_ observer: SignalProducer<Value, NoError>.ProducedSignal.Observer) {
        state.modify { (state: inout State) in
            guard let index = state.waiters.firstIndex(where: { $0.observer === observer }) else {
                fatalError()
            }

            if index == 0 {
                if state.lockedFirstEntry {
                    state.values.remove(at: 0)
                    state.lockedFirstEntry = false
                    state.waiters.remove(at: 0)
                }

                self.lockFirstEvent(state: &state)
            } else {
                fatalError("Trying to consume without sending an event!")
            }
        }
    }

    private func cancel(_ observer: SignalProducer<Value, NoError>.ProducedSignal.Observer) {
        state.modify { (state: inout State) in
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
        return NextValue(queue: self) { observer, lifetime in
            self.state.modify { (state: inout State) in
                state.waiters.append((observer, lifetime))
                
                self.lockFirstEvent(state: &state)
            }
        }
    }

    func enqueue(_ value: Value) {
        state.modify { (state: inout State) in
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

extension Reactor where Value == Never {
    var unwrappedState: Property<State> {
        return state.map { $0.unwrapped }
    }
}
