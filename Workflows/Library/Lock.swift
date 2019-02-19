import MachO

internal final class Lock {
    private let _lock: os_unfair_lock_t

    init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock())
    }

    func lock() {
        os_unfair_lock_lock(_lock)
    }

    func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    func `try`() -> Bool {
        return os_unfair_lock_trylock(_lock)
    }

    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }
}
