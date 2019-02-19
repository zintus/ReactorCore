import Foundation
import ReactiveSwift
import Result

func loadImage(url: String) -> SignalProducer<UIImage?, NoError> {
    return SignalProducer { observer, _ in
        DispatchQueue.global().async {
            observer.send(value: UIImage(data: try! Data(contentsOf: URL(string: url)!)))
            observer.sendCompleted()
        }
    }
}

func loadImageWorkflow(url: String) -> ReadonlyWorkflow<UIImage?> {
    return ReadonlyWorkflow(initialState: .run(loadImage(url: url)))
}

typealias ImageLoader = ReadonlyWorkflow<UIImage?>
