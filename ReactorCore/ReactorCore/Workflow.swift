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
    typealias CompleteState = WorkflowState<State, Value>

    var state: Property<WorkflowState<State, Value>> { get }

    func launch()
}

extension Workflow where Value == Never {
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

extension WorkflowState: Equatable where State: Equatable, Result: Equatable {}
