import Foundation
import ReactiveSwift
import Result

class ValueQueue2<Value> {
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
        
        private let queue: ValueQueue2<Value>
        
        private func tryToConsume() {
            if let value = value, let onValue = onValue {
                onValue(value)
                queue.consume()
            }
        }
        
        init(value: Value?, queue: ValueQueue2<Value>) {
            self.value = value
            self.queue = queue
            
            print("next init")
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

class ReactionBuilder2<Event, State, Value> {
    private let scheduler: QueueScheduler
    private let eventQueue: ValueQueue2<Event>

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
    
    init(_ scheduler: QueueScheduler, eventQueue: ValueQueue2<Event>) {
        self.scheduler = scheduler
        self.eventQueue = eventQueue
    }
    
    func workflowUpdatedFlatMap<W: Workflow>(
        _ handle: WorkflowHandle2<W>,
        mapper: @escaping (WorkflowHandle2<W>) -> SignalProducer<StateTransition<State, Value>?, NoError>
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
    
    func receivedFlatMap(_ mapper: @escaping (Event) -> SignalProducer<StateTransition<State, Value>?, NoError>) {
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

private class WorkflowStateTracker2<W: Workflow> {
    private let (lifetime, token) = Lifetime.make()
    private let stateQueue: ValueQueue2<W.CompleteState>
    
    init(workflow: W, scheduler: QueueScheduler) {
        stateQueue = ValueQueue2(scheduler)
        
        lifetime += workflow.state.signal
            .producer
            .observe(on: scheduler)
            .on { [weak self] value in
                self?.stateQueue.enqueue(value)
            }
            .start()
    }
    
    func firstState() -> ValueQueue2<W.CompleteState>.NextValue {
        return stateQueue.dequeue()
    }
    
    func unsafeState() -> W.CompleteState {
        let next = firstState()
        let value = next.value!
        stateQueue.consume()
        return value
    }
}

class WorkflowHandle2<W: Workflow> {
    private let workflow: W
    private let stateTracker: WorkflowStateTracker2<W>
    
    init(_ workflow: W, scheduler: QueueScheduler) {
        self.workflow = workflow
        let tracker = WorkflowStateTracker2(workflow: workflow, scheduler: scheduler)
        stateTracker = tracker
        state = workflow.state.value
        
        workflow.launch()
    }
    
    private init(workflow: W, stateTracker: WorkflowStateTracker2<W>, state: W.CompleteState) {
        self.workflow = workflow
        self.stateTracker = stateTracker
        self.state = state
    }
    
    let state: W.CompleteState
    
    func send(event: W.Event) {
        workflow.send(event: event)
    }
    
    fileprivate func toNextState() -> ValueQueue2<W.CompleteState>.NextValue {
        return stateTracker.firstState()
    }
    
    func withState(_ state: W.CompleteState) -> WorkflowHandle2<W> {
        return WorkflowHandle2(workflow: workflow, stateTracker: stateTracker, state: state)
    }
}

extension ReactionBuilder2 {
    func workflowUpdated<W: Workflow>(
        _ handle: WorkflowHandle2<W>,
        mapper: @escaping (WorkflowHandle2<W>) -> StateTransition<State, Value>?
        ) {
        workflowUpdatedFlatMap(handle) { handle in
            SignalProducer(value: mapper(handle))
        }
    }
    
    func received(_ mapper: @escaping (Event) -> StateTransition<State, Value>?) {
        receivedFlatMap { event in
            SignalProducer(value: mapper(event))
        }
    }
}
