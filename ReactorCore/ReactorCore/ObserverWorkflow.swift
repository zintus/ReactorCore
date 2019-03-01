import ReactiveSwift
import Result

public typealias SubscriptionState<Value> = WorkflowState<Value, Value>

public class ObserverWorkflow<T>: Workflow {
    public typealias Event = Readonly
    public typealias State = T
    public typealias Value = Never

    public enum Readonly {}

    private var producer: SignalProducer<T, NoError>?

    required init<R: PropertyProtocol>(with property: R) where R.Value == T {
        state = Property(capturing: property.map { CompleteState.running($0) })
    }

    public let state: Property<CompleteState>

    public func send(event _: Readonly) {}
}

public extension PropertyProtocol {
    func asWorkflow() -> ObserverWorkflow<Value> {
        return ObserverWorkflow(with: self)
    }
}
