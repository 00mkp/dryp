import ArgumentParser
import DrypCore
import Foundation

struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Start or stop the menu-bar agent, or set Open at Login.",
        subcommands: [Start.self, Stop.self, Login.self])

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch the agent and keep it in the menu bar.")

        func run() throws {
            let env = CLIEnvironment.current
            if env.agent.pid() == nil { StartMarker.touch(env.paths) }
            _ = env.agent.start()
            let deadline = Date().addingTimeInterval(env.waitTimeout)
            while env.agent.pid() == nil && Date() < deadline { Thread.sleep(forTimeInterval: env.pollInterval) }
            guard let pid = env.agent.pid() else {
                env.err("dryp: the agent didn't start (see \(env.paths.logFile.path))")
                throw ExitCode(1)
            }
            env.out("dryp is running (pid \(pid))")
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Quit the agent: stops both modes and restores sleep first.")

        func run() throws {
            let env = CLIEnvironment.current
            guard env.agent.stop() else {
                env.err("dryp: the agent didn't exit within 10 seconds")
                throw ExitCode(1)
            }
            let owned = AppliedStore(paths: env.paths).read().nosleepSet
            switch env.readSleepDisabled() {
            case true?:
                if owned {
                    env.err("dryp: stopped, but sleep is still disabled; run: \(PmsetCommand.manualRestore)")
                    throw ExitCode(1)
                }
                env.out("dryp stopped; sleep is still disabled (not by dryp) — run: \(PmsetCommand.manualRestore)")
            case nil:
                if owned {
                    env.err("dryp: stopped, but SleepDisabled couldn't be read; check with `pmset -g live` "
                            + "and if needed run: \(PmsetCommand.manualRestore)")
                    throw ExitCode(1)
                }
                env.out("dryp stopped; couldn't read SleepDisabled")
            case false?:
                env.out("dryp stopped; sleep is enabled")
            }
        }
    }

    struct Login: ParsableCommand {
        enum Setting: String, ExpressibleByArgument { case on, off }

        static let configuration = CommandConfiguration(abstract: "Open at Login: on or off.")

        @Argument var setting: Setting

        func run() throws {
            let env = CLIEnvironment.current
            do {
                try StateStore(paths: env.paths).update { $0.prefs.openAtLogin = setting == .on }
            } catch {
                env.err("dryp: \(error)")
                throw ExitCode(1)
            }
            env.out("Open at Login: \(setting.rawValue)")
        }
    }
}
