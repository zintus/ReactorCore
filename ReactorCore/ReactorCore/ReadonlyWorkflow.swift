import Foundation
import ReactiveSwift
import Result

public class ReadonlyWorkflow<Result>: Workflow, SingleLike {
    public typealias Event = Readonly
    public typealias Value = Result

    public enum Readonly {}
    public enum State {
        // Hide this better
        case run(SignalProducer<Result, NoError>)
    }

    public required init(initialState: State) {
        mutableState = MutableProperty(.running(initialState))
        state = Property(capturing: mutableState)
    }

    public func launch() {
        switch mutableState.value {
        case let .running(.run(producer)):
            mutableState <~ producer.map(WorkflowState.finished)
        case .finished:
            fatalError("Trying to start already finished workflow")
        }
    }

    private let mutableState: MutableProperty<CompleteState>
    public let state: Property<CompleteState>

    public func send(event _: Readonly) {}

    deinit {
        print("deinit")
    }
}

public extension SignalProducer where Error == NoError {
    func asWorkflow() -> ReadonlyWorkflow<Value> {
        return ReadonlyWorkflow(initialState: .run(self))
    }
}
