import ReactiveSwift
import Result

protocol Single {
    associatedtype Value
    func onReady(_ subscriber: @escaping (Value) -> Void)
}

class SingleSource<Value> {
    private let single: BaseSingle<Value>

    func fill(_ value: Value) {
        single.fill(value)
    }

    init(_ single: BaseSingle<Value>) {
        self.single = single
    }
}

extension Single {
    func map<R>(_ transform: @escaping (Value) -> R?) -> BaseSingle<R> {
        let (single, source) = BaseSingle<R>.pipe()

        onReady { value in
            if let transformed = transform(value) {
                source.fill(transformed)
            } else {
                fatalError("You have failed to handle \(value)")
            }
        }

        return single
    }
}

class BaseSingle<Value>: Single {
    private typealias State = (Value?, [(Value) -> Void])
    private let state = Atomic<State>((nil, []))
    private let isEmpty: Bool
    private let subscribersQueue = DispatchQueue(label: "Single")

    private init(isEmpty: Bool) {
        self.isEmpty = isEmpty
    }

    init(value: Value) {
        isEmpty = false
        state.swap((value, []))
    }

    fileprivate func fill(_ value: Value) {
        state.modify { (myState: inout State) -> Void in
            if myState.0 == nil {
                myState.0 = value
                for subscriber in myState.1 {
                    subscribersQueue.async {
                        subscriber(value)
                    }
                }
                myState.1 = []
            } else {
                fatalError()
            }
        }
    }

    static var empty: BaseSingle {
        return BaseSingle(isEmpty: true)
    }

    func onReady(_ subscriber: @escaping (Value) -> Void) {
        assert(!isEmpty)

        state.modify { (myState: inout State) -> Void in
            if let value = myState.0 {
                self.subscribersQueue.async {
                    subscriber(value)
                }
            } else {
                myState.1.append(subscriber)
            }
        }
    }

    static func pipe() -> (BaseSingle<Value>, SingleSource<Value>) {
        let single = BaseSingle<Value>(isEmpty: false)
        let source = SingleSource(single)

        return (single, source)
    }
}

extension SignalProducer {
    func asSingle() -> BaseSingle<Value> {
        let (single, source) = BaseSingle<Value>.pipe()

        take(first: 1)
            .on { value in
                source.fill(value)
            }
            .start()

        return single
    }
}

extension Single {
    func asSignalProducer() -> SignalProducer<Value, NoError> {
        return SignalProducer { observer, _ in
            self.onReady { value in
                observer.send(value: value)
                observer.sendCompleted()
            }
        }
    }
}

// Select

class SelectBuilder<S: Single, Result> {
    private let originalSingle: S
    init(single: S) {
        originalSingle = single
    }

    private var components = [() -> BaseSingle<Result>]()

    func workflowUpdate<W: Workflow>(_ workflow: W, mapping: @escaping (WorkflowState<W.State, W.Value>) -> Result) {
        components.append({
            workflow.state.producer.skip(first: 1).asSingle().map(mapping)
        })
    }

    func receivedEvent(_ mapping: @escaping (S.Value) -> Result?) {
        components.append({
            self.originalSingle.map(mapping)
        })
    }

    fileprivate func toSingle() -> BaseSingle<Result> {
        let (single, source) = BaseSingle<Result>.pipe()
        let filled = Atomic(false)
        for component in components {
            let single = component()
            single.onReady { value in
                let filled = filled.swap(true)
                if !filled {
                    source.fill(value)
                } else {
                    // This is solely problem with our design.
                    // To implement proper event consume we need to do two way communication across chain of singles
                    // Which we don't have right now
                    print("lost single")
                }
            }
            if filled.value {
                break
            }
        }
        components = []
        return single
    }
}

extension Single {
    func select<Result>(_ definition: (SelectBuilder<Self, Result>) -> Void) -> BaseSingle<Result> {
        let builder = SelectBuilder<Self, Result>(single: self)
        definition(builder)
        return builder.toSingle()
    }
}
