import Foundation
import ReactiveSwift
import Result

public protocol Single {
    associatedtype FinalState
    func onReady(_ subscriber: @escaping (FinalState) -> Void)
}

public enum WorkflowState<State, FinalState> {
    case running(State)
    case finished(FinalState)
}

public protocol Workflow: WorkflowInput, Single {
    associatedtype State
    typealias Handle = WorkflowHandle<Event, State, FinalState>
    typealias CompleteState = WorkflowState<State, FinalState>

    var state: Property<WorkflowState<State, FinalState>> { get }
}

public protocol WorkflowLauncher {
    func launch()
}

public extension Workflow where FinalState == Never {
    func onReady(_: @escaping (FinalState) -> Void) {
        // log error?
    }
}

public protocol WorkflowInput {
    associatedtype Event
    func send(event: Event)
}

public extension WorkflowState where FinalState == Never {
    var unwrapped: State {
        switch self {
        case let .running(state): return state
        }
    }
}

public extension Workflow where FinalState == Never {
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

extension WorkflowState: Equatable where State: Equatable, FinalState: Equatable {}

// MARK: - Handler

public extension Workflow {
    func handle(on scheduler: QueueScheduler) -> WorkflowHandle<Event, State, FinalState> {
        return WorkflowHandle(self, scheduler: scheduler)
    }
}

public extension Workflow where Self: WorkflowLauncher {
    func handle(on scheduler: QueueScheduler) -> WorkflowHandle<Event, State, FinalState> {
        let handle = WorkflowHandle(self, scheduler: scheduler)
        launch()
        return handle
    }
}
