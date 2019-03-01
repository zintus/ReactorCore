import Foundation
import ReactiveSwift
import Result

public class ValueQueue<Value> {
    private let scheduler: QueueScheduler
    init(_ scheduler: QueueScheduler) {
        self.scheduler = scheduler
    }

    private var storage: [Value] = []
    private weak var nextValue: NextValue?

    func enqueue(_ value: Value) {
        scheduler.schedule {
            self.storage.append(value)
            if let next = self.nextValue {
                if next.value == nil {
                    next.fill(self.storage[0])
                }
            }
        }
    }

    class NextValue {
        var onValue: ((Value) -> Void)? {
            didSet {
                if oldValue != nil {
                    fatalError("Can't set onValue more than once")
                }

                tryToConsume()
            }
        }

        private(set) var value: Value? {
            didSet {
                if oldValue != nil {
                    fatalError("Can't fill twice")
                }

                tryToConsume()
            }
        }

        private let queue: ValueQueue<Value>

        private func tryToConsume() {
            if let value = value, let onValue = onValue {
                onValue(value)
                queue.consume()
            }
        }

        init(value: Value?, queue: ValueQueue<Value>) {
            self.value = value
            self.queue = queue
        }

        func fill(_ value: Value) {
            self.value = value
        }
    }

    func dequeue() -> NextValue {
        if nextValue != nil {
            fatalError("Trying to get second nextValue")
        }

        let result = NextValue(value: storage.first, queue: self)
        nextValue = result
        return result
    }

    fileprivate func consume() {
        nextValue = nil
        storage.remove(at: 0)
    }
}

public class ReactionBuilder<Event, State, Value> {
    private let scheduler: QueueScheduler
    private let eventQueue: ValueQueue<(Event, DispatchSemaphore?)>

    private var awaitingNexts: [AnyObject]? = []
    let futureState = FutureState()

    private let (lifetime, token) = Lifetime.make()

    class FutureState {
        typealias ValueAndSemaphore = (StateTransition<State, Value>, DispatchSemaphore?)
        var onValue: ((ValueAndSemaphore) -> Void)? {
            didSet {
                if oldValue != nil {
                    fatalError("Can't set onValue more than once")
                }

                tryToConsume()
            }
        }

        var value: ValueAndSemaphore? {
            didSet {
                if oldValue != nil {
                    fatalError("Can't fill twice")
                }

                tryToConsume()
            }
        }

        private func tryToConsume() {
            if let value = value, let onValue = onValue {
                onValue(value)
            }
        }
    }

    init(_ scheduler: QueueScheduler, eventQueue: ValueQueue<(Event, DispatchSemaphore?)>) {
        self.scheduler = scheduler
        self.eventQueue = eventQueue
    }

    public func workflowUpdatedFlatMap<W: Workflow>(
        _ handle: WorkflowHandle<W>,
        mapper: @escaping (WorkflowHandle<W>) -> SignalProducer<StateTransition<State, Value>?, NoError>
    ) {
        guard awaitingNexts != nil else {
            // Someone already computed next state
            return
        }
        let nextState = handle.toNextState()
        nextState.onValue = { [weak self] newState in
            guard let self = self else { return }

            self.awaitingNexts = nil

            let newHandle = handle.withState(newState)
            self.lifetime += mapper(newHandle)
                .take(first: 1)
                .observe(on: self.scheduler)
                .on { [weak self] transition in
                    guard let transition = transition else {
                        fatalError("Unhandled state transition")
                    }
                    guard let self = self else { return }

                    self.futureState.value = (transition, nil)
                }
                .start()
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        awaitingNexts = nexts + [nextState]
    }

    public func receivedFlatMap(_ mapper: @escaping (Event) -> SignalProducer<StateTransition<State, Value>?, NoError>) {
        guard awaitingNexts != nil else {
            // Someone already computed next state
            return
        }
        let nextState = eventQueue.dequeue()
        nextState.onValue = { [weak self] newState in
            guard let self = self else { return }

            self.awaitingNexts = nil

            self.lifetime += mapper(newState.0)
                .take(first: 1)
                .observe(on: self.scheduler)
                .on { [weak self] transition in
                    guard let transition = transition else {
                        fatalError("Unhandled state transition")
                    }

                    guard let self = self else { return }

                    self.futureState.value = (transition, newState.1)
                }
                .start()
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        awaitingNexts = nexts + [nextState]
    }
}

private class WorkflowStateTracker<W: Workflow> {
    private let (lifetime, token) = Lifetime.make()
    private let stateQueue: ValueQueue<W.CompleteState>

    init(workflow: W, scheduler: QueueScheduler) {
        stateQueue = ValueQueue(scheduler)

        lifetime += workflow.state.signal
            .producer
            .observe(on: scheduler)
            .on { [weak self] value in
                self?.stateQueue.enqueue(value)
            }
            .start()
    }

    func firstState() -> ValueQueue<W.CompleteState>.NextValue {
        return stateQueue.dequeue()
    }

    func unsafeState() -> W.CompleteState {
        let next = firstState()
        let value = next.value!
        stateQueue.consume()
        return value
    }
}

public class WorkflowHandle<W: Workflow> {
    private let workflow: W
    private let stateTracker: WorkflowStateTracker<W>

    public init(_ workflow: W, scheduler: QueueScheduler) {
        self.workflow = workflow
        let tracker = WorkflowStateTracker(workflow: workflow, scheduler: scheduler)
        stateTracker = tracker
        state = workflow.state.value
    }

    private init(workflow: W, stateTracker: WorkflowStateTracker<W>, state: W.CompleteState) {
        self.workflow = workflow
        self.stateTracker = stateTracker
        self.state = state
    }

    public let state: W.CompleteState

    public func send(event: W.Event) {
        workflow.send(event: event)
    }

    fileprivate func toNextState() -> ValueQueue<W.CompleteState>.NextValue {
        return stateTracker.firstState()
    }

    func withState(_ state: W.CompleteState) -> WorkflowHandle<W> {
        return WorkflowHandle(workflow: workflow, stateTracker: stateTracker, state: state)
    }
}

public extension WorkflowHandle where W: WorkflowLauncher {
    static func makeAndLaunch(_ workflow: W, scheduler: QueueScheduler) -> WorkflowHandle {
        let handle = WorkflowHandle(workflow, scheduler: scheduler)
        workflow.launch()
        return handle
    }
}

// WARN: Don't edit this, copy paste from above
extension ReactionBuilder {
    public func workflowUpdated<W: Workflow>(
        _ handle: WorkflowHandle<W>,
        mapper: @escaping (WorkflowHandle<W>) -> StateTransition<State, Value>?
    ) {
        guard awaitingNexts != nil else {
            // Someone already computed next state
            return
        }
        let nextState = handle.toNextState()
        nextState.onValue = { [weak self] newState in
            guard let self = self else { return }

            self.awaitingNexts = nil

            let newHandle = handle.withState(newState)

            guard let transition = mapper(newHandle) else {
                fatalError("Unhandled transition")
            }

            self.futureState.value = (transition, nil)
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        awaitingNexts = nexts + [nextState]
    }

    public func received(_ mapper: @escaping (Event) -> StateTransition<State, Value>?) {
        guard awaitingNexts != nil else {
            // Someone already computed next state
            return
        }
        let nextState = eventQueue.dequeue()
        nextState.onValue = { [weak self] newState in
            guard let self = self else { return }

            self.awaitingNexts = nil

            guard let transition = mapper(newState.0) else {
                fatalError("Unhandled transition")
            }

            self.futureState.value = (transition, newState.1)
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        awaitingNexts = nexts + [nextState]
    }
}
