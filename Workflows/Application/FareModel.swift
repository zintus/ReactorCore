import Foundation
import ReactiveSwift
import Result

typealias Fare = Int

// Polls fares with certain interval
class FareModel: BaseReactor<FareModel.Event, FareModel.State, Never> {
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
        to state: State,
        eventSource _: SignalProducer<Event, NoError>
    ) -> Reaction<State, Never> {
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
