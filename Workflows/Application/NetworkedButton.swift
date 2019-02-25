import Foundation
import ReactiveSwift
import Result
import ReactorCore

class NetworkedButton: ReactorCore<NetworkedButton.Event, NetworkedButton.State, Never> {
    enum State {
        case initial
        case loading
        case loaded(title: String)
    }

    enum Event {
        case touchUpInside
        case touchUpOutside
        case fareUpdated(fare: Fare)
    }

    init() {
        super.init(initialState: .initial)

        fareModel.state.producer
            .on { [weak self] state in
                switch state {
                case let .running(.loaded(fare: fare)):
                    self?.send(event: .fareUpdated(fare: fare))
                default: break
                }
            }
            .start()
        fareModel.launch()
    }

    private let fareModel = FareModel()

    // State definition
    override func react(
        to state: State
    ) -> Reaction<Event, State, Never> {
        switch state {
        case .initial, .loaded:
            return buildEventReaction { event in
                switch event {
                case .touchUpInside:
                    return .enterState(.loading)

                case let .fareUpdated(fare):
                    return .enterState(.loaded(title: String(fare)))

                default:
                    return nil
                }
            }

        case .loading:
            return Reaction(makeNetworkRequest().map { .enterState(.loaded(title: $0)) })
        }
    }

    deinit {
        print("~ deinit")
    }
}

// Fictional network request
func makeNetworkRequest() -> SignalProducer<String, NoError> {
    return SignalProducer(value: Int(arc4random()))
        .delay(1, on: QueueScheduler())
        .map { counter in String(counter) }
}
