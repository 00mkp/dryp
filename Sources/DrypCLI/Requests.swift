import DrypCore
import Foundation

/// Write a request, wait for the agent to acknowledge it, and report the real result.
enum Requests {
    static func start(_ mode: Mode, seconds: TimeInterval?, env: CLIEnvironment) -> Int32 {
        let now = env.now().wholeSeconds
        let session = Session(started: now, until: seconds.map { now.addingTimeInterval($0) })
        let store = StateStore(paths: env.paths)
        let written: DrypState
        do {
            written = try store.update { $0[mode] = session }
        } catch {
            env.err("dryp: \(error)")
            return 1
        }
        guard let applied = awaitAck(rev: written.rev, env: env) else {
            // Roll back (only this exact session) so the agent can't apply it later after we said it failed.
            _ = try? store.clear([mode: session])
            return notResponding(env, cancelled: true)
        }
        if let r = applied.rejected, r.mode == mode, r.rev >= written.rev {
            env.err("dryp: \(r.reason)")
            return 1
        }
        guard store.current()[mode] == session else {
            env.err("dryp: the \(mode.rawValue) request was replaced by another one before it took effect")
            return 1
        }
        if mode == .caf && !applied.cafHeld {
            env.err("dryp: caf was accepted but the power assertions aren't held — see `dryp status`")
            return 1
        }
        if mode == .nosleep && env.readSleepDisabled() != true {
            env.err("dryp: nosleep was accepted but SleepDisabled isn't 1 — see `dryp status`")
            return 1
        }
        env.out(Format.started(mode, session))
        return 0
    }

    static func stop(_ modes: [Mode], env: CLIEnvironment) -> Int32 {
        let store = StateStore(paths: env.paths)
        let touchesSleep = modes.contains(.nosleep)
        let written: DrypState
        do {
            written = try store.update { s in
                for m in modes { s[m] = nil }
                if touchesSleep { s.restoreSleep = true }
            }
        } catch {
            env.err("dryp: \(error)")
            return 1
        }
        guard let applied = awaitAck(rev: written.rev, env: env) else { return notResponding(env) }
        if modes.contains(.caf) && applied.cafHeld {
            env.err("dryp: caf was stopped but the power assertions are still held — see `dryp status`")
            return 1
        }
        if touchesSleep {
            switch env.readSleepDisabled() {
            case true?:
                env.err("dryp: sleep is still disabled; run: \(PmsetCommand.manualRestore)")
                return 1
            case nil:
                env.err("dryp: couldn't read SleepDisabled — see `dryp status`")
                return 1
            case false?:
                break
            }
        }
        switch (modes.count, touchesSleep) {
        case (2, _): env.out("off; sleep is enabled")
        case (_, true): env.out("nosleep off; sleep is enabled")
        default: env.out("\(modes[0].rawValue) off")
        }
        return 0
    }

    /// Waits for applied.rev to reach `rev`. Starts the agent if it isn't running, and retries once.
    static func awaitAck(rev: Int, env: CLIEnvironment) -> Applied? {
        let applied = AppliedStore(paths: env.paths)
        func poll() -> Applied? {
            let deadline = Date().addingTimeInterval(env.waitTimeout)
            repeat {
                let a = applied.read()
                if a.rev >= rev { return a }
                Thread.sleep(forTimeInterval: env.pollInterval)
            } while Date() < deadline
            return nil
        }
        if env.agent.pid() == nil {
            _ = env.agent.start()
        } else {
            env.agent.nudge()
        }
        if let a = poll() { return a }
        _ = env.agent.start()
        return poll()
    }

    private static func notResponding(_ env: CLIEnvironment, cancelled: Bool = false) -> Int32 {
        env.err("dryp: the dryp agent isn't responding (see \(env.paths.logFile.path))"
                + (cancelled ? "; the request was cancelled" : ""))
        return 1
    }
}
