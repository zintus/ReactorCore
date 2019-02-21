import UIKit

private extension TrainingViewModel {
    func process(input: Event) {
        send(event: input)
    }

    func addReactor(_ reactor: @escaping (State) -> Void) {
        state.producer.on { value in
            switch value {
            case let .running(state): reactor(state)
            default: break
            }
        }
        .start()
    }
}

class TestController: UIViewController {
    @IBOutlet private var imageView: UIImageView!
    @IBOutlet private var imageLoader: UIActivityIndicatorView!
    @IBOutlet private var label: UILabel!
    @IBOutlet private var textField: UITextField!
    @IBOutlet private var button1: UIButton!
    @IBOutlet private var button2: UIButton!
    @IBOutlet private var cancelButon: UIButton!

    @IBAction private func onButton1Pressed() {
        viewModel.process(input: .loadImage(textField.text!))
    }

    @IBAction private func onButton2Pressed() {
        viewModel.process(input: .increaseCounter)
    }

    @IBAction private func cancelImageLoad() {
        viewModel.process(input: .cancelImageLoad)
    }

    private let viewModel = TrainingViewModel(initialState: .makeInitial())

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.addReactor { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateImageView(state: state.imageLoader?.state)
                self.updateLabel(state: state.labelState)
                self.updateTextField(state: state.textFieldState)
                self.updateButton1State(state: state.buttonState)
                self.updateCancelButtonState(isImageLoading: state.isImageLoading)
            }
        }

        // Can't figure out pasteboard :(
        textField.text = "https://static.independent.co.uk/s3fs-public/thumbnails/image/2017/09/12/11/naturo-monkey-selfie.jpg?w968"
        viewModel.send(event: .textInput(textField.text!))

//        viewModel.launch()
    }

    private func updateCancelButtonState(isImageLoading: Bool) {
        cancelButon.isEnabled = isImageLoading
    }

    private func updateImageView(state: ImageLoader.CompleteState?) {
        if let state = state {
            switch state {
            case .running:
                imageLoader.startAnimating()

            case let .finished(image):
                imageLoader.stopAnimating()
                imageView.image = image
            }
        } else {
            imageLoader.stopAnimating()
            imageView.image = UIImage(named: "Placeholder")
        }
    }

    private func updateLabel(state: TrainingViewModel.LabelState) {
        switch state {
        case .placeholder:
            label.text = "Counter value: 0.\nPress Button2 for update."
        case let .value(text):
            label.text = text
        }
    }

    private func updateTextField(state: TrainingViewModel.TextFieldState) {
        switch state {
        case .normal:
            textField.placeholder = "Enter image URL"
            textField.textColor = .black
        case .error:
            textField.textColor = .red
        }
    }

    private func updateButton1State(state: ButtonViewModel.State) {
        switch state {
        case .disabled:
            button1.isEnabled = false
        case .normal:
            button1.isEnabled = true
        }
    }
}

extension TestController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let newString = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) {
            viewModel.process(input: .textInput(newString))
        }
        return true
    }
}
