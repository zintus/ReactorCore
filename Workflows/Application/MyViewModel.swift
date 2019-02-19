import Foundation
import ReactiveSwift
import Result

class MyViewModel: ReactorCore<MyViewModel.Event, MyViewModel.ViewState, ()> {
    struct ViewState {
        let leftButton: WorkflowHandle<NetworkedButton>
        let rightButton: WorkflowHandle<NetworkedButton>
    }

    enum Event {
        case pressLeftButton
        case pressRightButton
        case cancelBothButtons
    }

    init() {
        super.init(initialState: ViewState(
            leftButton: WorkflowHandle(NetworkedButton()),
            rightButton: WorkflowHandle(NetworkedButton())
        ))
    }

    private var counter = 0

    override func react(
        to state: ViewState,
        eventSource: SignalProducer<Event, NoError>
    ) -> Reaction<ViewState, ()> {
        if counter < 10 {
            counter += 1
        } else {
            // Test subworkflow deallocation
            return Reaction(value: .finishWith(()))
        }

        return buildReaction { when in
            when.workflowUpdated(state.leftButton) { handle in
                .enterState(ViewState(leftButton: handle, rightButton: state.rightButton))
            }

            when.workflowUpdated(state.rightButton) { handle in
                .enterState(ViewState(leftButton: state.leftButton, rightButton: handle))
            }

            when.receivedEvent(eventSource) { event in
                switch event {
                case .pressLeftButton: state.leftButton.send(event: .touchUpInside)
                case .pressRightButton: state.rightButton.send(event: .touchUpInside)
                case .cancelBothButtons: break
                }

                // It's possible to provide variant without return statement
                return .enterState(state)
            }
        }
    }
}
