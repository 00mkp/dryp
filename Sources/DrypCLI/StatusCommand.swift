import ArgumentParser
import DrypCore
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show both modes, the real SleepDisabled value, and the agent. Never starts the agent.")

    func run() throws {
        let env = CLIEnvironment.current
        Status.lines(env: env, timeZone: .current).forEach(env.out)
    }

    static func lines(env: CLIEnvironment, timeZone: TimeZone) -> [String] {
        let state = StateStore(paths: env.paths).current()
        let applied = AppliedStore(paths: env.paths).read()
        let now = env.now()
        let live = env.readSleepDisabled()
        let pid = env.agent.pid()

        var lines = ["caf:      " + Format.status(state.caf, now: now, timeZone: timeZone)]
        if state.nosleep == nil && !env.nosleepInstalled() {
            lines.append("nosleep:  not set up — run ./install.sh --nosleep")
        } else {
            lines.append("nosleep:  " + Format.status(state.nosleep, now: now, timeZone: timeZone))
        }
        lines.append("pmset:    " + (live.map { "SleepDisabled \($0 ? 1 : 0)" } ?? "unknown"))
        lines.append("agent:    " + (pid.map { "running (pid \($0))" } ?? "not running"))

        if applied.restoreFailed && live == true {
            lines.append("warning:  dryp couldn't restore sleep — run: \(PmsetCommand.manualRestore)")
        } else if live == true && state.nosleep == nil {
            lines.append("warning:  sleep is disabled but dryp's nosleep is off — run `dryp nosleep off` or use Restore Sleep in the menu")
        } else if live == false && state.nosleep != nil && pid != nil {
            lines.append("warning:  nosleep is on but SleepDisabled is 0 — see \(env.paths.logFile.path)")
        }
        return lines
    }
}
