import Foundation
import ReactiveSwift

class AnyWorkflow<E, S, V>: Workflow {
    typealias Event = E
    typealias State = S
    typealias FinalState = V

    init<W: Workflow>(_ workflow: W) where
        W.Event == Event,
        W.State == State,
        W.FinalState == FinalState
    {
        state = workflow.state

        _onReady = workflow.onReady
        _send = workflow.send
    }

    let state: Property<WorkflowState<S, V>>

    private let _send: (E) -> Void
    func send(event: Event) {
        _send(event)
    }

    private let _onReady: (@escaping (V) -> Void) -> Void
    func onReady(_ subscriber: @escaping (V) -> Void) {
        _onReady(subscriber)
    }
}
