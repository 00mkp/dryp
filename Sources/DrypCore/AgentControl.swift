import Foundation

public enum Launchctl {
    public static var domain: String { "gui/\(getuid())" }
    public static var target: String { "\(domain)/\(Paths.label)" }

    public static func pid(fromPrint output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid = ") { return Int(trimmed.dropFirst("pid = ".count)) }
        }
        return nil
    }
}

/// How the CLI (and the Finder handoff) reach the launchd-managed agent. Injectable for tests.
public struct AgentControl {
    /// The agent's pid, or nil if it isn't running.
    public var pid: () -> Int?
    /// Loads (bootstrap) or starts (kickstart) the agent. True if launchctl succeeded.
    public var start: () -> Bool
    /// Sends SIGTERM (the agent runs its shutdown routine) and waits up to 10 s for it to exit.
    public var stop: () -> Bool
    /// Called after every state write. The live agent notices through its file watcher, so this is a no-op;
    /// tests reconcile synchronously here.
    public var nudge: () -> Void

    public init(pid: @escaping () -> Int?, start: @escaping () -> Bool, stop: @escaping () -> Bool,
                nudge: @escaping () -> Void = {}) {
        self.pid = pid
        self.start = start
        self.stop = stop
        self.nudge = nudge
    }

    public static func live(paths: Paths) -> AgentControl {
        let launchctl = "/bin/launchctl"
        func printed() -> Shell.Result { Shell.run(launchctl, ["print", Launchctl.target]) }
        func pid() -> Int? {
            let r = printed()
            return r.status == 0 ? Launchctl.pid(fromPrint: r.output) : nil
        }
        return AgentControl(
            pid: pid,
            start: {
                if printed().status != 0 {
                    return Shell.run(launchctl, ["bootstrap", Launchctl.domain, paths.launchAgentPlist.path]).status == 0
                }
                return Shell.run(launchctl, ["kickstart", Launchctl.target]).status == 0
            },
            stop: {
                guard pid() != nil else { return true }
                _ = Shell.run(launchctl, ["kill", "SIGTERM", Launchctl.target])
                let deadline = Date().addingTimeInterval(10)
                while pid() != nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                return pid() == nil
            })
    }
}
