import Foundation
import ReactiveSwift
import Result

class ButtonViewModel: ReactorCore<ButtonViewModel.Event, ButtonViewModel.ViewState, Never> {
    enum Event {
        case changeURL(String)
        case imageIsLoading(Bool)
        case imageLoaded
    }

    enum ViewState {
        case normal
        case disabled
    }

    init() {
        super.init(initialState: .disabled)
    }

    private var url: String = ""
    private var isValidURL: Bool {
        // Simplification...
        return URL(string: url)?.scheme != nil
    }

    override func react(
        to state: ViewState
    ) -> Reaction<ViewState, Never> {
        return buildReaction { [weak self] when in
            when.received { event in
                guard let self = self else { return .enterState(state) }

                print("button state")

                switch event {
                case .imageLoaded:
                    return .enterState(.disabled)

                case let .changeURL(url):
                    self.url = url

                case let .imageIsLoading(isLoading):
                    if isLoading {
                        return .enterState(.disabled)
                    }
                }

                return .enterState(self.isValidURL ? .normal : .disabled)
            }
        }
    }
}
