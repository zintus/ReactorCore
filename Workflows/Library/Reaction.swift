import Foundation
import ReactiveSwift
import Result

// Pure syntactic sugar
enum StateTransition<State, Value> {
    case enterState(State)
    case finishWith(Value)
}

class ReactionBuilder<Event, State, Value> {
    fileprivate typealias Producer = SignalProducer<StateTransition<State, Value>, NoError>
    private var producers: [Producer] = []
    private let scheduler: Scheduler
    private let eventQueue: ValueQueue<Event>

    init(_ scheduler: Scheduler, eventQueue: ValueQueue<Event>) {
        self.scheduler = scheduler
        self.eventQueue = eventQueue
    }

    private let zeroProducersStarted = Atomic(true)

    func workflowUpdated<W: Workflow>(
        _ handle: WorkflowHandle<W>,
        mapper: @escaping (WorkflowHandle<W>) -> StateTransition<State, Value>?
    ) {
        workflowUpdatedFlatMap(handle) { handle in
            SignalProducer(value: mapper(handle))
        }
    }

    func workflowUpdatedFlatMap<W: Workflow>(
        _ handle: WorkflowHandle<W>,
        mapper: @escaping (WorkflowHandle<W>) -> SignalProducer<StateTransition<State, Value>?, NoError>
    ) {
        let nextState = handle.toNextState()
        let zeroProducersStarted = self.zeroProducersStarted

        producers.append(
            nextState.producer
                .observe(on: scheduler)
                .filter { _ in
                    return zeroProducersStarted.value
                }
                .on(terminated: {
                    nextState.cancel()
                }, value: { _ in
                    zeroProducersStarted.swap(false)
                    nextState.consume()
                })
                .map({ handle.withState($0) })
                .flatMap(.latest, mapper)
                .map { transition -> StateTransition<State, Value> in
                    guard let transition = transition else {
                        fatalError("Unhandled workflow state")
                    }

                    return transition
                }
        )
    }

    func received(_ mapper: @escaping (Event) -> StateTransition<State, Value>?) {
        receivedFlatMap { event in
            SignalProducer(value: mapper(event))
        }
    }

    func receivedFlatMap(_ mapper: @escaping (Event) -> SignalProducer<StateTransition<State, Value>?, NoError>) {
        let nextEvent = eventQueue.nextValue()
        let zeroProducersStarted = self.zeroProducersStarted

        producers.append(nextEvent.producer
            .observe(on: scheduler)
            .filter { _ in
                zeroProducersStarted.value
            }
            .on(terminated: {
                nextEvent.cancel()
            }, value: { _ in
                zeroProducersStarted.swap(false)
                nextEvent.consume()
            })
            .flatMap(.latest, mapper)
            .map { transition -> StateTransition<State, Value> in
                guard let transition = transition else {
                    fatalError("Unhandled event")
                }

                return transition
        })
    }

    fileprivate func build() -> Producer {
        return Producer.merge(producers)
    }
}

class Reaction<Event, State, Value> {
    let signalProducer: SignalProducer<StateTransition<State, Value>, NoError>

    init(
        scheduler: QueueScheduler,
        eventQueue: ValueQueue2<Event>,
        _ builderBlock: (ReactionBuilder2<Event, State, Value>) -> Void
    ) {
        let builder = ReactionBuilder2<Event, State, Value>(scheduler, eventQueue: eventQueue)
        builderBlock(builder)
        signalProducer = SignalProducer { observer, lifetime in
            builder.futureState.onValue = { value in
                observer.send(value: value)
                observer.sendCompleted()
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

// MARK: - Delegation

private class WorkflowStateTracker<W: Workflow> {
    private let (lifetime, token) = Lifetime.make()
    private let stateQueue = ValueQueue<W.CompleteState>()

    init(workflow: W) {
        lifetime += workflow.state.producer
            .on { [weak self] value in
                self?.stateQueue.enqueue(value)
            }
            .start()
    }

    func firstState() -> ValueQueue<W.CompleteState>.NextValue {
        return stateQueue.nextValue()
    }
}

class WorkflowHandle<W: Workflow>: WorkflowInput {
    private let workflow: W
    private let stateTracker: WorkflowStateTracker<W>

    init(_ workflow: W) {
        self.workflow = workflow
        stateTracker = WorkflowStateTracker(workflow: workflow)
        let nextState = stateTracker.firstState()
        state = nextState.producer.take(first: 1).single()!.value! // Guaranteed by first sync state
        nextState.consume()
        workflow.launch()
    }

    private init(workflow: W, stateTracker: WorkflowStateTracker<W>, state: W.CompleteState) {
        self.workflow = workflow
        self.stateTracker = stateTracker
        self.state = state
    }

    let state: W.CompleteState

    func send(event: W.Event) {
        workflow.send(event: event)
    }

    fileprivate func toNextState() -> ValueQueue<W.CompleteState>.NextValue {
        return stateTracker.firstState()
    }

    func withState(_ state: W.CompleteState) -> WorkflowHandle<W> {
        return WorkflowHandle(workflow: workflow, stateTracker: stateTracker, state: state)
    }
}
