import Dispatch
import Foundation
import ReactiveSwift
import Result

public protocol Reactor: class, Workflow, WorkflowLauncher, SingleLike {
    func react(
        to state: State
    ) -> Reaction<Event, State, FinalState>

    func buildReaction(
        _ builderBlock: (ReactionBuilder<Event, State, FinalState>) -> Void
    ) -> Reaction<Event, State, FinalState>
    func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, FinalState>?
    ) -> Reaction<Event, State, FinalState>
}

open class ReactorCore<T1, T2, T3>: Reactor {
    public typealias Event = T1
    public typealias State = T2
    public typealias FinalState = T3
    public typealias StateTransitionProducer = SignalProducer<StateTransition<T2, T3>, NoError>

    public init(initialState: T2, scheduler: QueueScheduler = QueueScheduler(name: "ReactorCore.Scheduler")) {
        (lifetime, token) = Lifetime.make()
        self.scheduler = scheduler
        mutableState = MutableProperty(CompleteState.running(initialState))
        state = Property(capturing: mutableState)
        eventQueue = ValueQueue<(T1, DispatchSemaphore?)>(scheduler)
    }

    private var launched: Bool = false
    private let mutableState: MutableProperty<CompleteState>
    public let state: Property<CompleteState>

    open func react(
        to _: T2
    ) -> Reaction<T1, T2, T3> {
        fatalError()
    }

    public func launch() {
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

    private let eventQueue: ValueQueue<(T1, DispatchSemaphore?)>

    public func send(event: T1) {
        eventQueue.enqueue((event, nil))
    }

    public func send(syncEvent event: T1) {
        let semaphore = DispatchSemaphore(value: 0)
        eventQueue.enqueue((event, semaphore))
        semaphore.wait()
    }

    private func buildState(_ initialState: State) -> Property<WorkflowState<T2, T3>> {
        typealias CompleteState = WorkflowState<T2, T3>

        let continueStateStream = { [weak self] (_ prev: CompleteState) -> SignalProducer<CompleteState, NoError> in
            guard let self = self else { return .empty }

            switch prev {
            case .finished:
                return .empty

            case let .running(current):
                return self.react(to: current)
                    .signalProducer
                    .map { $0.nextState }
            }
        }

        let result: SignalProducer<CompleteState, NoError> = SignalProducer { [weak self] observer, lifetime in
            var currentState = CompleteState.running(initialState)

            var subscribeNextState: (() -> Void)!

            subscribeNextState = { [weak self] in
                guard let self = self else { return }

                lifetime += self.scheduler.schedule {
                    lifetime += continueStateStream(currentState)
                        .on { nextState in
                            currentState = nextState
                            observer.send(value: nextState)

                            subscribeNextState()
                        }
                        .start()
                }
            }

            subscribeNextState()
        }

        let first = CompleteState.running(initialState)
        return Property(initial: first, then: result)
    }

    // MARK: - Build Reactions

    public let scheduler: QueueScheduler

    public func buildReaction(
        _ builderBlock: (ReactionBuilder<Event, State, FinalState>) -> Void
    ) -> Reaction<Event, State, FinalState> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue, builderBlock)
    }

    public func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, FinalState>?
    ) -> Reaction<Event, State, FinalState> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue) { when in
            when.received(mapper)
        }
    }

    // MARK: - Lifetime

    public let lifetime: Lifetime
    private let token: Lifetime.Token
}

// Only purpose of this is sugar
private extension StateTransition {
    var nextState: WorkflowState<State, FinalState> {
        switch self {
        case let .enterState(state): return .running(state)
        case let .finishWith(value): return .finished(value)
        }
    }
}

extension SignalProducer where Error == NoError {
    static func enterState<State, FullState>(
        _ state: State
    ) -> SignalProducer<StateTransition<State, FullState>, Error> {
        return SignalProducer<StateTransition<State, FullState>, Error>(value: .enterState(state))
    }

    static func finishWith<State, FullState>(
        _ state: FullState
    ) -> SignalProducer<StateTransition<State, FullState>, Error> {
        return SignalProducer<StateTransition<State, FullState>, Error>(value: .finishWith(state))
    }
}
