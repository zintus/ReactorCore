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
    private let eventQueue: ValueQueue<Event>

    private var awaitingNexts: [AnyObject]? = []
    let futureState = FutureState()
    
    private let (lifetime, token) = Lifetime.make()
    
    class FutureState {
        var onValue: ((StateTransition<State, Value>) -> Void)? {
            didSet {
                if oldValue != nil {
                    fatalError("Can't set onValue more than once")
                }
                
                tryToConsume()
            }
        }
        
        var value: StateTransition<State, Value>? {
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
    
    init(_ scheduler: QueueScheduler, eventQueue: ValueQueue<Event>) {
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
                    
                    self.futureState.value = transition
                }
                .start()
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        self.awaitingNexts = nexts + [nextState]
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

            self.lifetime += mapper(newState)
                .take(first: 1)
                .observe(on: self.scheduler)
                .on { [weak self] transition in
                    guard let transition = transition else {
                        fatalError("Unhandled state transition")
                    }
                    
                    guard let self = self else { return }
                    
                    self.futureState.value = transition
                }
                .start()
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        self.awaitingNexts = nexts + [nextState]
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
        
        workflow.launch()
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
            self.futureState.value = mapper(newHandle)
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        self.awaitingNexts = nexts + [nextState]
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
            
            self.futureState.value = mapper(newState)
        }
        guard let nexts = awaitingNexts else {
            // Someone already computed next state
            return
        }
        self.awaitingNexts = nexts + [nextState]
    }
}
