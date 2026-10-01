import DrypCore
import Foundation

/// Everything the CLI touches outside its own logic — injectable so tests use a fake home and agent.
public struct CLIEnvironment {
    public var paths: Paths
    public var now: () -> Date
    public var readSleepDisabled: () -> Bool?
    /// Whether /etc/sudoers.d/dryp exists (for `status`).
    public var nosleepInstalled: () -> Bool
    public var agent: AgentControl
    /// Runs a tool attached to the terminal (git, install.sh, sudo rm). Returns its exit status.
    public var run: (String, [String], [String: String]) -> Int32
    /// Whether a git checkout has an upstream branch to pull from (`dryp update`).
    public var hasUpstream: (String) -> Bool
    public var waitTimeout: TimeInterval
    public var pollInterval: TimeInterval
    public var out: (String) -> Void
    public var err: (String) -> Void

    public init(paths: Paths, now: @escaping () -> Date, readSleepDisabled: @escaping () -> Bool?,
                nosleepInstalled: @escaping () -> Bool, agent: AgentControl,
                run: @escaping (String, [String], [String: String]) -> Int32,
                hasUpstream: @escaping (String) -> Bool,
                waitTimeout: TimeInterval, pollInterval: TimeInterval,
                out: @escaping (String) -> Void, err: @escaping (String) -> Void) {
        self.paths = paths
        self.now = now
        self.readSleepDisabled = readSleepDisabled
        self.nosleepInstalled = nosleepInstalled
        self.agent = agent
        self.run = run
        self.hasUpstream = hasUpstream
        self.waitTimeout = waitTimeout
        self.pollInterval = pollInterval
        self.out = out
        self.err = err
    }

    public static var live: CLIEnvironment {
        let paths = Paths.live
        return CLIEnvironment(
            paths: paths,
            now: Date.init,
            readSleepDisabled: Shell.liveSleepDisabled,
            nosleepInstalled: { FileManager.default.fileExists(atPath: Paths.sudoersFile.path) },
            agent: .live(paths: paths),
            run: { Shell.interactive($0, $1, environment: $2) },
            hasUpstream: { source in
                Shell.run("/usr/bin/git", ["-C", source, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).status == 0
            },
            waitTimeout: 2,
            pollInterval: 0.05,
            out: { print($0) },
            err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
    }

    @TaskLocal public static var current: CLIEnvironment = .live
}
