import Foundation
import ReactiveSwift
import Result

public protocol SingleLike {
    associatedtype State
    associatedtype Value
    var state: Property<WorkflowState<State, Value>> { get }
}

extension SingleLike {
    public func onReady(_ continuation: @escaping (Value) -> Void) {
        state
            .producer
            .flatMap(.concat) { state -> SignalProducer<Value, NoError> in
                switch state {
                case let .finished(result): return SignalProducer(value: result)
                case .running: return .empty
                }
            }
            .take(first: 1)
            .on(value: continuation)
            .start()
    }
}
