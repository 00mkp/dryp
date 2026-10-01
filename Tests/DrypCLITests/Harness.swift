import Foundation
import Testing
@testable import DrypCLI
@testable import DrypCore

final class FakeAssertions: PowerAssertions {
    var isHeld = false
    var ignoreHold = false
    func hold() throws { if !ignoreHold { isHeld = true } }
    func release() { isHeld = false }
}

final class FakeSleep: SleepSetting {
    var available = true
    var disabled = false
    var ineffectiveSets = 0
    func isAvailable() -> Bool { available }
    func set(disabled value: Bool) -> Bool {
        if ineffectiveSets > 0 { ineffectiveSets -= 1; return false }
        disabled = value
        return true
    }
    func read() -> Bool? { disabled }
}

final class FakePower: PowerSource {
    var info = PowerInfo.ac
    func current() -> PowerInfo { info }
}

final class NullNotifier: Notifier { func post(_ notice: Notice) {} }

/// A CLI run against a fake home with an in-process "agent": every state write is reconciled immediately.
final class CLIHarness {
    let paths: Paths
    let caf = FakeAssertions()
    let sleep = FakeSleep()
    let power = FakePower()
    var agentRunning = true
    var agentResponds = true
    var startCalls = 0
    var stopCalls = 0
    var runs: [(String, [String], [String: String])] = []
    var runStatus: Int32 = 0
    var hasUpstream = true
    var nosleepInstalled = true
    var sleepReadOverride: Bool?? = nil
    var out: [String] = []
    var err: [String] = []
    let now = Date(timeIntervalSince1970: 1_790_784_000)
    lazy var reconciler = Reconciler(
        store: StateStore(paths: paths), appliedStore: AppliedStore(paths: paths), caf: caf, sleep: sleep,
        power: power, notifier: NullNotifier(), now: { [unowned self] in self.now },
        bootTime: now.addingTimeInterval(-86_400), log: { _ in })

    init() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("dryp-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = Paths(home: home)
    }

    var env: CLIEnvironment {
        CLIEnvironment(
            paths: paths,
            now: { [unowned self] in self.now },
            readSleepDisabled: { [unowned self] in self.sleepReadOverride ?? self.sleep.disabled },
            nosleepInstalled: { [unowned self] in self.nosleepInstalled },
            agent: AgentControl(
                pid: { [unowned self] in self.agentRunning ? 4411 : nil },
                start: { [unowned self] in
                    self.startCalls += 1
                    self.agentRunning = true
                    if self.agentResponds { self.reconciler.reconcile() }
                    return true
                },
                stop: { [unowned self] in
                    self.stopCalls += 1
                    self.reconciler.shutdown()
                    self.agentRunning = false
                    return true
                },
                nudge: { [unowned self] in
                    if self.agentRunning && self.agentResponds { self.reconciler.reconcile() }
                }),
            run: { [unowned self] path, args, environment in
                self.runs.append((path, args, environment))
                return self.runStatus
            },
            hasUpstream: { [unowned self] _ in self.hasUpstream },
            waitTimeout: 0.2,
            pollInterval: 0.01,
            out: { [unowned self] in self.out.append($0) },
            err: { [unowned self] in self.err.append($0) })
    }

    @discardableResult
    func dryp(_ args: String...) -> Int32 {
        CLIEnvironment.$current.withValue(env) { DrypMain.run(args) }
    }

    var state: DrypState { StateStore(paths: paths).current() }
}
