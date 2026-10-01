import Foundation
@testable import DrypCore

struct FakeError: Error {}

final class FakeAssertions: PowerAssertions {
    var isHeld = false
    var failHold = false
    func hold() throws {
        if failHold { throw FakeError() }
        isHeld = true
    }
    func release() { isHeld = false }
}

/// Simulates `sudo pmset` and `pmset -g live`.
final class FakeSleep: SleepSetting {
    var available = true
    var disabled = false
    /// While > 0, `set` calls run but change nothing (and count down).
    var ineffectiveSets = 0
    var setCalls: [Bool] = []

    func isAvailable() -> Bool { available }
    func set(disabled value: Bool) -> Bool {
        setCalls.append(value)
        if ineffectiveSets > 0 { ineffectiveSets -= 1; return false }
        disabled = value
        return true
    }
    func read() -> Bool? { disabled }
}

final class FakePower: PowerSource {
    var info = PowerInfo.ac
    /// Runs (once) the next time the reconciler asks for power info: simulates another process writing mid-pass.
    var onCurrent: (() -> Void)?
    func current() -> PowerInfo {
        if let hook = onCurrent { onCurrent = nil; hook() }
        return info
    }
}

final class FakeNotifier: Notifier {
    var posted: [Notice] = []
    func post(_ notice: Notice) { posted.append(notice) }
}

final class TestClock {
    var now = t0
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// One fake world: a temp home, the stores, the fakes, and a reconciler wired to them.
final class World {
    let paths: Paths
    let store: StateStore
    let appliedStore: AppliedStore
    let caf = FakeAssertions()
    let sleep = FakeSleep()
    let power = FakePower()
    let notifier = FakeNotifier()
    let clock = TestClock()
    var logs: [String] = []
    var boot = t0.addingTimeInterval(-86_400)
    private(set) var reconciler: Reconciler!

    init(home: URL? = nil) throws {
        paths = Paths(home: try home ?? tempHome())
        store = StateStore(paths: paths)
        appliedStore = AppliedStore(paths: paths)
        restartAgent()
    }

    /// A fresh Reconciler over the same files, as after a crash (the fakes keep their state, like the OS).
    func restartAgent() {
        caf.isHeld = false   // assertions die with the process
        reconciler = Reconciler(store: store, appliedStore: appliedStore, caf: caf, sleep: sleep, power: power,
                                notifier: notifier, now: { [unowned self] in self.clock.now }, bootTime: boot,
                                log: { [unowned self] in self.logs.append($0) })
    }

    func request(_ mode: Mode, for length: TimeInterval?) throws {
        let now = clock.now
        try store.update { $0[mode] = Session(started: now, until: length.map { now.addingTimeInterval($0) }) }
    }

    func stop(_ mode: Mode) throws { try store.update { $0[mode] = nil } }
}
