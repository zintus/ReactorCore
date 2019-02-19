import Foundation
import ReactiveSwift
import Result

// Pure syntactic sugar
enum StateTransition<State, Value> {
    case enterState(State)
    case finishWith(Value)
}

// FIXME: First one who have their event sent to mapper wins race, and cancel everyone else
class ReactionBuilder<State, Value> {
    fileprivate typealias Producer = SignalProducer<StateTransition<State, Value>, NoError>
    private var producers: [Producer] = []
    private let scheduler: Scheduler
    init(_ scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    func workflowUpdated<W: Workflow>(
        _ handle: WorkflowHandle<W>,
        mapper: @escaping (WorkflowHandle<W>) -> StateTransition<State, Value>
    ) {
        let nextState = handle.toNextState()
        producers.append(
            nextState.value.producer
                .skipNil()
                .observe(on: scheduler)
                .logEvents(identifier: "workflowUpdated")
                .on(interrupted: {
                    nextState.cancel()
                }, value: { _ in
                    nextState.consume()
                })
                .map { handle.withState($0) }
                .map(mapper)
        )
    }

    func receivedEvent<Event>(_ event: SignalProducer<Event, NoError>,
                              _ mapper: @escaping (Event) -> StateTransition<State, Value>?) {
        producers.append(event
            .observe(on: scheduler)
            .map(mapper)
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

class Reaction<State, Value> {
    let signalProducer: SignalProducer<StateTransition<State, Value>, NoError>

    init(scheduler: Scheduler, _ builderBlock: (ReactionBuilder<State, Value>) -> Void) {
        let builder = ReactionBuilder<State, Value>(scheduler)
        builderBlock(builder)
        signalProducer = builder.build()
    }

    init(_ signalProducer: SignalProducer<StateTransition<State, Value>, NoError>) {
        self.signalProducer = signalProducer
    }

    init(value: StateTransition<State, Value>) {
        signalProducer = SignalProducer(value: value)
    }
}

class EventReaction<Event, State, Value>: Reaction<State, Value> {
    init(scheduler: Scheduler,
         _ event: SignalProducer<Event, NoError>,
         _ mapper: @escaping (Event) -> StateTransition<State, Value>?) {
        super.init(scheduler: scheduler) { when in
            when.receivedEvent(event, mapper)
        }
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
        state = nextState.value.value! // Guaranteed by first sync state
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
