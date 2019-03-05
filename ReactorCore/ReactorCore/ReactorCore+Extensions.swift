import ReactiveSwift

public protocol LifetimeProvider: class {
    var lifetime: Lifetime { get }
}

extension WorkflowInput where Self: LifetimeProvider {
    public var events: BindingTarget<Event> {
        return BindingTarget(lifetime: lifetime) { [weak self] event in
            self?.send(event: event)
        }
    }
}
