import Foundation

/// The agent's brain. Every input — file change, timer, battery, wake, clock change, menu action — calls
/// `reconcile()`, which reads the requests, decides, makes the drivers match, and records what it did.
public final class Reconciler {
    private let store: StateStore
    private let appliedStore: AppliedStore
    private let caf: PowerAssertions
    private let sleep: SleepSetting
    private let power: PowerSource
    private let notifier: Notifier
    private let now: () -> Date
    private let bootTime: Date
    private let log: (String) -> Void

    public private(set) var state = DrypState()
    public private(set) var applied: Applied
    public private(set) var foreign = false
    public private(set) var nosleepAvailable: Bool

    private var warned = Set<WarningKey>()
    private var foreignNotified = false
    private var restoreFailures = 0
    private var nextRetry: Date?

    public init(store: StateStore, appliedStore: AppliedStore, caf: PowerAssertions, sleep: SleepSetting,
                power: PowerSource, notifier: Notifier, now: @escaping () -> Date, bootTime: Date,
                log: @escaping (String) -> Void) {
        self.store = store
        self.appliedStore = appliedStore
        self.caf = caf
        self.sleep = sleep
        self.power = power
        self.notifier = notifier
        self.now = now
        self.bootTime = bootTime
        self.log = log
        applied = appliedStore.read()
        nosleepAvailable = sleep.isAvailable()
    }

    public func refreshAvailability() { nosleepAvailable = sleep.isAvailable() }

    /// Returns when the agent next needs to look (a warning, a deadline, or a restore retry), or nil.
    @discardableResult
    public func reconcile() -> Date? {
        let t = now()
        if store.read() == .corrupt, (try? store.quarantineCorrupt()) == true {
            log("state.json was unreadable; moved it to state.json.bad")
        }
        var current = store.current()
        if current.nosleep != nil && !applied.nosleepSet { nosleepAvailable = sleep.isAvailable() }

        let decision = Policy.decide(Observation(now: t, bootTime: bootTime, state: current, applied: applied,
                                                 power: power.current(), nosleepAvailable: nosleepAvailable))
        if let r = decision.rejection { reject(r) }
        if !decision.clear.isEmpty { current = clear(decision.clear, fallback: current) }

        if decision.holdCaf && !caf.isHeld {
            do {
                try caf.hold()
                log("caf: assertions held")
            } catch {
                reject(Rejection(mode: .caf, reason: "couldn't create the power assertions (\(error))", rev: current.rev))
                if let s = current.caf { current = clear([.caf: s], fallback: current) }
            }
        } else if !decision.holdCaf && caf.isHeld {
            caf.release()
            log("caf: assertions released")
        }

        if decision.disableSleep {
            if !disableSleep(rev: current.rev), let s = current.nosleep { current = clear([.nosleep: s], fallback: current) }
        } else {
            restoreSleepIfOwned(at: t)
        }

        current = handleRestoreRequest(current, disabling: decision.disableSleep && current.nosleep != nil)

        let live = sleep.read()
        foreign = live == true && !applied.nosleepSet
        if foreign && !foreignNotified {
            notifier.post(.foreignSleepDisabled)
            log("sleep is disabled outside dryp")
        }
        foreignNotified = foreign

        for e in decision.endings {
            notifier.post(.ended(e))
            log("\(e.mode.rawValue): ended (\(e.reason))")
        }
        for mode in Schedule.dueWarnings(current, now: t, warned: warned) {
            if let until = current[mode]?.until { warned.insert(WarningKey(mode: mode, until: until)) }
            notifier.post(.warning(mode))
        }

        state = current
        applied.rev = current.rev
        applied.cafHeld = caf.isHeld
        persistApplied()

        let wake = Schedule.nextWake(current, now: t, warned: warned)
        let retry = applied.restoreFailed ? nextRetry : nil
        return [wake, retry].compactMap { $0 }.min()
    }

    /// Adds `seconds` to a timed session's deadline. No-op for unlimited or stopped modes.
    public func extend(_ mode: Mode, by seconds: TimeInterval) {
        do {
            try store.update { s in
                guard var session = s[mode], let until = session.until else { return }
                session.until = until.addingTimeInterval(seconds)
                s[mode] = session
            }
            log("\(mode.rawValue): extended by \(Int(seconds / 60))m")
        } catch {
            log("extend failed: \(error)")
        }
    }

    /// Completed in Task 9.
    @discardableResult
    public func shutdown() -> Bool { true }

    // MARK: - Steps

    private func reject(_ r: Rejection) {
        applied.rejected = r
        log("rejected \(r.mode.rawValue): \(r.reason)")
    }

    private func clear(_ sessions: [Mode: Session], fallback: DrypState) -> DrypState {
        do {
            return try store.clear(sessions)
        } catch {
            log("couldn't write state.json: \(error)")
            return fallback
        }
    }

    /// Makes SleepDisabled 1 and owned. False (with a rejection) if pmset didn't take.
    private func disableSleep(rev: Int) -> Bool {
        if sleep.read() == true {
            if !applied.nosleepSet { log("nosleep: sleep was already disabled; dryp now owns it") }
            applied.nosleepSet = true
            return true
        }
        sleep.set(disabled: true)
        guard sleep.read() == true else {
            reject(Rejection(mode: .nosleep, reason: "pmset didn't disable sleep (see ~/Library/Logs/dryp.log)", rev: rev))
            return false
        }
        applied.nosleepSet = true
        log("nosleep: sleep disabled")
        return true
    }

    /// Completed in Task 9 (retries and failure reporting). Happy path: restore and disown.
    private func restoreSleepIfOwned(at t: Date) {
        guard applied.nosleepSet else { return }
        sleep.set(disabled: false)
        if sleep.read() == false {
            applied.nosleepSet = false
            log("nosleep: sleep restored")
        }
    }

    /// Completed in Task 9.
    private func handleRestoreRequest(_ current: DrypState, disabling: Bool) -> DrypState { current }

    private func persistApplied() {
        do { try appliedStore.write(applied) } catch { log("couldn't write applied.json: \(error)") }
    }
}
