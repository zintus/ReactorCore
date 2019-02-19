import Foundation
import ReactiveSwift
import Result

// build copy of training example
// cancel button for image loading
// subworkflow: load image (.loading, .loaded)

// ApplicationWorkflow
//  - OnboardingWorkflow(ask for user profile, ask for push permissions)
//  - AuthorizedWorkflow(deeplink, show active rides count)
//   - ConfirmationViewModel(==)
//    - AcceptOfferViewModel
//   - FareViewModel

enum WorkflowState<State, Result> {
    case running(State)
    case finished(Result)
}

protocol Workflow: WorkflowInput, Single {
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

protocol WorkflowInput {
    associatedtype Event
    func send(event: Event)
}

extension WorkflowState where Result == Never {
    var unwrapped: State {
        switch self {
        case let .running(state): return state
        }
    }
}
