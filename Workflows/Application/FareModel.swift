import Foundation
import ReactiveSwift
import Result
import ReactorCore

typealias Fare = Int

// Polls fares with certain interval
class FareModel: ReactorCore<FareModel.Event, FareModel.State, Never> {
    enum State {
        case loading
        case loaded(fare: Fare)
    }

    enum Event {}

    init() {
        super.init(initialState: .loading)
    }

    // State definition
    override func react(
        to state: State
    ) -> Reaction<Event, State, Never> {
        switch state {
        case .loading:
            return Reaction(
                SignalProducer(value: Int(arc4random()))
                    .map { .enterState(.loaded(fare: $0)) }
            )

        case .loaded:
            return Reaction(
                SignalProducer(value: Int(arc4random()))
                    .delay(7, on: QueueScheduler())
                    .map { _ in .enterState(.loading) }
            )
        }
    }
}
