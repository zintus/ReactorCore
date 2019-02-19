import Foundation
import ReactiveSwift
import Result

class ReadonlyWorkflow<Result>: Workflow, SingleLike {
    typealias Event = Readonly
    typealias Value = Result

    enum Readonly {}
    enum State {
        // Hide this better
        case run(SignalProducer<Result, NoError>)
    }

    required init(initialState: State) {
        mutableState = MutableProperty(.running(initialState))
        state = Property(capturing: mutableState)
    }

    func launch() {
        switch mutableState.value {
        case let .running(.run(producer)):
            mutableState <~ producer.map(WorkflowState.finished)
        case .finished:
            fatalError("Trying to start already finished workflow")
        }
    }

    private let mutableState: MutableProperty<CompleteState>
    let state: Property<CompleteState>

    func send(event _: Readonly) {}

    deinit {
        print("deinit")
    }
}

extension SignalProducer where Error == NoError {
    func asWorkflow() -> ReadonlyWorkflow<Value> {
        return ReadonlyWorkflow(initialState: .run(self))
    }
}
