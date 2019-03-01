import Foundation
import ReactiveSwift
import Result

public protocol Single {
    associatedtype Value
    func onReady(_ subscriber: @escaping (Value) -> Void)
}

public enum WorkflowState<State, Result> {
    case running(State)
    case finished(Result)
}

public protocol Workflow: WorkflowInput, Single {
    associatedtype State
    typealias Handle = WorkflowHandle<Event, State, Value>
    typealias CompleteState = WorkflowState<State, Value>

    var state: Property<WorkflowState<State, Value>> { get }
}

public protocol WorkflowLauncher {
    func launch()
}

public extension Workflow where Value == Never {
    func onReady(_: @escaping (Value) -> Void) {
        // log error?
    }
}

public protocol WorkflowInput {
    associatedtype Event
    func send(event: Event)
}

public extension WorkflowState where Result == Never {
    var unwrapped: State {
        switch self {
        case let .running(state): return state
        }
    }
}

public extension Workflow where Value == Never {
    var unwrappedState: Property<State> {
        return state.map { $0.unwrapped }
    }
}

public extension WorkflowState {
    var runningState: State? {
        switch self {
        case let .running(state): return state
        default: return nil
        }
    }
}

extension WorkflowState: Equatable where State: Equatable, Result: Equatable {}

// MARK: - Handler

public extension Workflow {
    func handle(on scheduler: QueueScheduler) -> WorkflowHandle<Event, State, Value> {
        return WorkflowHandle(self, scheduler: scheduler)
    }
}

public extension Workflow where Self: WorkflowLauncher {
    func handle(on scheduler: QueueScheduler) -> WorkflowHandle<Event, State, Value> {
        let handle = WorkflowHandle(self, scheduler: scheduler)
        launch()
        return handle
    }
}
