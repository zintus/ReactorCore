import ReactiveSwift
import Result

public typealias SubscriptionState<Value> = WorkflowState<Value, Value>

public class SubscriptionWorkflow<T: SignalProducerConvertible>: Workflow where T.Error == NoError {
    public typealias Event = Readonly
    public typealias State = T.Value?
    public typealias Value = T.Value?

    public enum Readonly {}

    private var producer: T?

    public required init(with producer: T) {
        self.producer = producer
        mutableState = MutableProperty(.running(nil))
        state = Property(capturing: mutableState)
    }

    public func launch() {
        if let producer = producer {
            self.producer = nil

            var lastState: T.Value?
            mutableState <~ producer.producer
                .on { lastState = $0 }
                .map { (value: T.Value) -> CompleteState in
                    CompleteState.running(Optional(value))
                }
                .on(completed: { [weak self] in
                    self?.mutableState.value = CompleteState.finished(lastState)
                })
        } else {
            fatalError()
        }
    }

    private let mutableState: MutableProperty<CompleteState>
    public let state: Property<CompleteState>

    public func send(event _: Readonly) {}

    private let (lifetime, token) = Lifetime.make()
    public func onReady(_ subscriber: @escaping (T.Value?) -> Void) {
        lifetime += state.producer
            .flatMap(.concat) { state -> SignalProducer<T.Value?, T.Error> in
                switch state {
                case .running: return .empty
                case let .finished(state): return SignalProducer(value: state)
                }
            }
            .take(first: 1)
            .on { subscriber($0) }
            .start()
    }
}

public extension SignalProducer where Error == NoError {
    func asWorkflow() -> SubscriptionWorkflow<SignalProducer> {
        return SubscriptionWorkflow(with: self)
    }
}
