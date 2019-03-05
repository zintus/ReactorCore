import Foundation
import ReactiveSwift
import Result

public protocol SingleLike {
    associatedtype State
    associatedtype Result
    var state: Property<WorkflowState<State, Result>> { get }
}

extension SingleLike {
    public func onReady(_ continuation: @escaping (Result) -> Void) {
        state
            .producer
            .flatMap(.concat) { state -> SignalProducer<Result, NoError> in
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
