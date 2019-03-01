import Dispatch
import Foundation
import ReactiveSwift
import Result

public protocol Reactor: class, Workflow, WorkflowLauncher, SingleLike {
    func react(
        to state: State
    ) -> Reaction<Event, State, Value>

    func buildReaction(
        _ builderBlock: (ReactionBuilder<Event, State, Value>) -> Void
    ) -> Reaction<Event, State, Value>
    func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, Value>?
    ) -> Reaction<Event, State, Value>
}

open class ReactorCore<E, S, R>: Reactor {
    public typealias Event = E
    public typealias State = S
    public typealias Value = R

    public init(initialState: S, scheduler: QueueScheduler = QueueScheduler(name: "ReactorCore.Scheduler")) {
        self.scheduler = scheduler
        mutableState = MutableProperty(CompleteState.running(initialState))
        state = Property(capturing: mutableState)
        eventQueue = ValueQueue<(E, DispatchSemaphore?)>(scheduler)
    }

    private var launched: Bool = false
    private let mutableState: MutableProperty<CompleteState>
    public let state: Property<CompleteState>

    open func react(
        to _: S
    ) -> Reaction<E, S, R> {
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

    private let eventQueue: ValueQueue<(E, DispatchSemaphore?)>

    public func send(event: E) {
        eventQueue.enqueue((event, nil))
    }

    public func send(syncEvent event: E) {
        let semaphore = DispatchSemaphore(value: 0)
        eventQueue.enqueue((event, semaphore))
        semaphore.wait()
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
        _ builderBlock: (ReactionBuilder<Event, State, Value>) -> Void
    ) -> Reaction<Event, State, Value> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue, builderBlock)
    }

    public func buildEventReaction(
        _ mapper: @escaping (Event) -> StateTransition<State, Value>?
    ) -> Reaction<Event, State, Value> {
        return Reaction(scheduler: scheduler, eventQueue: eventQueue) { when in
            when.received(mapper)
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
