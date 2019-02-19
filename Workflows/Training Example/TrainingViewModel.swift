import ReactiveSwift
import Result
import UIKit

class TrainingViewModel: ReactorCore<TrainingViewModel.Event, TrainingViewModel.OverallState, Never> {
    enum Event {
        case loadImage(String)
        case textInput(String)
        case increaseCounter
        case cancelImageLoad
    }

    enum LabelState {
        case placeholder
        case value(String)
    }

    enum TextFieldState {
        case normal
        case error
    }

    struct OverallState {
        let counter: Int
        let imageLoader: WorkflowHandle<ImageLoader>?
        let labelState: LabelState
        let textFieldState: TextFieldState
        fileprivate let button1State: WorkflowHandle<ButtonViewModel>
        var buttonState: ButtonViewModel.State {
            return button1State.state.unwrapped.withCounter(counter)
        }
        
        static func makeInitial() -> OverallState {
            return OverallState(counter: 0,
                                imageLoader: nil,
                                labelState: .placeholder,
                                textFieldState: .error,
                                button1State: WorkflowHandle(ButtonViewModel()))
        }

        fileprivate func with(counter: Int) -> OverallState {
            return OverallState(counter: counter,
                                imageLoader: imageLoader,
                                labelState: .value(String(counter)),
                                textFieldState: textFieldState,
                                button1State: button1State)
        }

        fileprivate func stopImageLoad() -> OverallState {
            if let loader = imageLoader, case .running = loader.state {
                return OverallState(counter: counter,
                                    imageLoader: nil,
                                    labelState: labelState,
                                    textFieldState: textFieldState,
                                    button1State: button1State)
            }

            return self
        }

        fileprivate func withImageLoader(_ loader: WorkflowHandle<ImageLoader>) -> OverallState {
            return OverallState(counter: counter,
                                imageLoader: loader,
                                labelState: labelState,
                                textFieldState: textFieldState,
                                button1State: button1State)
        }

        var isImageLoading: Bool {
            if case .running? = imageLoader?.state {
                return true
            }

            return false
        }

        fileprivate func withButton(_ button: WorkflowHandle<ButtonViewModel>) -> OverallState {
            return OverallState(counter: counter,
                                imageLoader: imageLoader,
                                labelState: labelState,
                                textFieldState: textFieldState,
                                button1State: button)
        }
    }

    // Переходы: зависят от текущего состояния
    // Если прийдёт ивент, то ... (1)
    // или если обновится состояние загрузчика картинок, то ... (2)
    // или если обновится состояние кнопки, то ... (3)
    
    
    // (1)/(2)
    // (2)/(1)

    override func react(
        to state: OverallState,
        eventSource: SignalProducer<Event, NoError>
    ) -> Reaction<OverallState, Never> {
        return buildReaction { when in
            // (1)
            when.receivedEvent(eventSource) { event in
                switch event {
                case .increaseCounter:
                    return .enterState(state.with(counter: state.counter + 1))

                case .cancelImageLoad:
                    state.button1State.send(event: .imageIsLoading(false))
                    return .enterState(state.stopImageLoad())

                case let .loadImage(url):
                    state.button1State.send(event: .imageIsLoading(true))
                    let workflow = loadImageWorkflow(url: url)
                    let imageLoadingHandle = WorkflowHandle(workflow)
                    return .enterState(state.withImageLoader(imageLoadingHandle))

                case let .textInput(text):
                    state.button1State.send(event: .changeURL(text))

                    return .enterState(state)
                }
            }

            if let image = state.imageLoader {
                // (2)
                when.workflowUpdated(image) { handle in
                    let newState = state.withImageLoader(handle)

                    switch handle.state {
                    case .finished:
                        newState.button1State.send(event: .imageLoaded)
                    case .running:
                        newState.button1State.send(event: .imageIsLoading(newState.isImageLoading))
                    }

                    return .enterState(newState)
                }
            }

            // (3)
            when.workflowUpdated(state.button1State) { handle in
                return .enterState(state.withButton(handle))
            }
        }
    }
}

fileprivate extension ButtonViewModel.State {
    func withCounter(_ counter: Int) -> ButtonViewModel.State {
        if counter % 2 == 0 {
            return .disabled
        } else {
            return self
        }
    }
}