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
    public func reconcile() -> Date? { reconcile(depth: 0, carried: []) }

    /// Seconds to wait before retrying when state.json can't be written (avoids a busy loop on a stale deadline).
    private static let writeFailureBackoff: TimeInterval = 30
    private static let maxRestarts = 3

    /// `carried` holds endings whose sessions an earlier, restarted pass already cleared.
    private func reconcile(depth: Int, carried: [Ending]) -> Date? {
        let t = now()
        if store.read() == .corrupt, (try? store.quarantineCorrupt()) == true {
            log("state.json was unreadable; moved it to state.json.bad")
        }
        var current = store.current()
        if current.nosleep != nil && !applied.nosleepSet { nosleepAvailable = sleep.isAvailable() }

        let decision = Policy.decide(Observation(now: t, bootTime: bootTime, state: current, applied: applied,
                                                 power: power.current(), nosleepAvailable: nosleepAvailable))
        if let r = decision.rejection { reject(r) }
        var endings = carried + decision.endings
        var clearFailed = false
        if !decision.clear.isEmpty {
            let observed = current
            var expected = observed
            for mode in decision.clear.keys { expected[mode] = nil }
            let result = clear(decision.clear, fallback: observed)
            current = result
            // A cleared session that is still there means the write failed: don't announce its end yet.
            let failed = decision.clear.filter { current[$0.key] == $0.value }
            if !failed.isEmpty {
                clearFailed = true
                endings.removeAll { failed[$0.mode] != nil }
            } else {
                var a = current, b = expected
                a.rev = 0; b.rev = 0
                // Another writer changed the requests mid-pass: the decision is stale, so redo it before
                // touching any driver.
                if a != b && depth < Reconciler.maxRestarts {
                    log("state.json changed during reconcile; deciding again")
                    return reconcile(depth: depth + 1, carried: endings)
                }
            }
        }

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

        var restoreAttempted = false
        if decision.disableSleep {
            if !disableSleep(rev: current.rev), let s = current.nosleep { current = clear([.nosleep: s], fallback: current) }
        } else {
            restoreAttempted = restoreSleepIfOwned(at: t)
        }

        current = handleRestoreRequest(current, disabling: decision.disableSleep && current.nosleep != nil,
                                       restoreAttempted: restoreAttempted)

        let live = sleep.read()
        foreign = live == true && !applied.nosleepSet
        if foreign && !foreignNotified {
            notifier.post(.foreignSleepDisabled)
            log("sleep is disabled outside dryp")
        }
        foreignNotified = foreign

        for e in endings {
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

        var wake = Schedule.nextWake(current, now: t, warned: warned)
        if clearFailed {
            let earliest = t.addingTimeInterval(Reconciler.writeFailureBackoff)
            wake = max(wake ?? earliest, earliest)
        }
        let retry = applied.restoreFailed ? nextRetry : nil
        return [wake, retry].compactMap { $0 }.min().map { max($0, t) }
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

    /// Quit, `dryp app stop`, uninstall, logout and SIGTERM all end here. Clears both modes first so nothing
    /// resumes them, releases the caf hold, and restores sleep if dryp set it. Returns true when
    /// SleepDisabled reads 0 (or dryp never set it). A foreign disablesleep is left alone.
    @discardableResult
    public func shutdown() -> Bool {
        do {
            try store.update { s in
                s.caf = nil
                s.nosleep = nil
            }
        } catch {
            log("shutdown: couldn't clear state.json: \(error)")
        }
        if caf.isHeld {
            caf.release()
            log("caf: assertions released (shutdown)")
        }
        var restored = true
        if applied.nosleepSet {
            sleep.set(disabled: false)
            restored = sleep.read() == false
            if restored {
                applied.nosleepSet = false
                applied.restoreFailed = false
                log("shutdown: sleep restored")
            } else {
                applied.restoreFailed = true
                log("shutdown: couldn't restore sleep")
            }
        }
        state = store.current()
        applied.rev = state.rev
        applied.cafHeld = false
        persistApplied()
        return restored
    }

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
            clearRestoreFailure()
            return true
        }
        sleep.set(disabled: true)
        guard sleep.read() == true else {
            reject(Rejection(mode: .nosleep, reason: "pmset didn't disable sleep (see ~/Library/Logs/dryp.log)", rev: rev))
            return false
        }
        applied.nosleepSet = true
        clearRestoreFailure()
        log("nosleep: sleep disabled")
        return true
    }

    private func clearRestoreFailure() {
        applied.restoreFailed = false
        restoreFailures = 0
        nextRetry = nil
    }

    /// Restores sleep if dryp set it. On failure: flag, notify once, and retry on the backoff schedule.
    /// Returns whether it ran pmset this pass.
    @discardableResult
    private func restoreSleepIfOwned(at t: Date) -> Bool {
        guard applied.nosleepSet else { return false }
        if applied.restoreFailed, let next = nextRetry, t < next { return false }
        sleep.set(disabled: false)
        if sleep.read() == false {
            applied.nosleepSet = false
            log(applied.restoreFailed ? "nosleep: sleep restored after \(restoreFailures) failed attempts" : "nosleep: sleep restored")
            applied.restoreFailed = false
            restoreFailures = 0
            nextRetry = nil
        } else {
            restoreFailures += 1
            let delay = Schedule.retryDelay(afterFailures: restoreFailures)
            nextRetry = t.addingTimeInterval(delay)
            if !applied.restoreFailed { notifier.post(.restoreFailed) }
            applied.restoreFailed = true
            log("nosleep: restore failed, retrying in \(Int(delay))s")
        }
        return true
    }

    /// The one-shot `restoreSleep` request (`dryp nosleep off`, `dryp off`, menu Restore Sleep / Retry):
    /// undo a foreign disablesleep or retry a failed restore now. Ignored while nosleep is wanted.
    private func handleRestoreRequest(_ current: DrypState, disabling: Bool, restoreAttempted: Bool) -> DrypState {
        guard current.restoreSleep else { return current }
        if !disabling {
            if applied.nosleepSet {
                // Only bypass a pending backoff; a pass that already tried must not try twice.
                if !restoreAttempted {
                    nextRetry = nil
                    restoreSleepIfOwned(at: now())
                }
            } else if sleep.read() == true {
                sleep.set(disabled: false)
                log(sleep.read() == false ? "restored sleep disabled outside dryp (by request)"
                                          : "couldn't restore sleep disabled outside dryp")
            }
        }
        do {
            return try store.update { $0.restoreSleep = false }
        } catch {
            log("couldn't clear restoreSleep: \(error)")
            return current
        }
    }

    private func persistApplied() {
        do { try appliedStore.write(applied) } catch { log("couldn't write applied.json: \(error)") }
    }
}
