import Foundation
import Testing
@testable import DrypCLI
@testable import DrypCore

@Suite struct StatusAndAppTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func statusShowsBothModesPmsetAndAgent() throws {
        let h = try CLIHarness()
        h.dryp("caf", "52")
        h.dryp("nosleep")
        let lines = Status.lines(env: h.env, timeZone: utc)
        #expect(lines == [
            "caf:      on · 52m left (until 16:52)",
            "nosleep:  on · no limit",
            "pmset:    SleepDisabled 1",
            "agent:    running (pid 4411)",
        ])
    }

    @Test func statusFlagsForeignSleep() throws {
        let h = try CLIHarness()
        h.sleep.disabled = true
        let lines = Status.lines(env: h.env, timeZone: utc)
        #expect(lines.contains("warning:  sleep is disabled but dryp's nosleep is off — run `dryp nosleep off` or use Restore Sleep in the menu"))
    }

    @Test func statusFlagsFailedRestore() throws {
        let h = try CLIHarness()
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        h.dryp("nosleep", "off")
        #expect(Status.lines(env: h.env, timeZone: utc).contains("warning:  dryp couldn't restore sleep — run: sudo pmset -a disablesleep 0"))
    }

    @Test func statusWhenNotSetUpAndNotRunning() throws {
        let h = try CLIHarness()
        h.nosleepInstalled = false
        h.agentRunning = false
        let lines = Status.lines(env: h.env, timeZone: utc)
        #expect(lines[1] == "nosleep:  not set up — run ./install.sh --nosleep")
        #expect(lines.last == "agent:    not running")
        #expect(h.startCalls == 0)       // status never starts the agent
    }

    @Test func appStartWritesTheMarkerAndStarts() throws {
        let h = try CLIHarness()
        h.agentRunning = false
        #expect(h.dryp("app", "start") == 0)
        #expect(h.startCalls == 1)
        #expect(FileManager.default.fileExists(atPath: h.paths.startMarker.path))
        #expect(h.out.last == "dryp is running (pid 4411)")
    }

    @Test func appStopShutsDownAndRestores() throws {
        let h = try CLIHarness()
        h.dryp("nosleep")
        #expect(h.dryp("app", "stop") == 0)
        #expect(h.stopCalls == 1)
        #expect(!h.sleep.disabled)
        #expect(h.out.last == "dryp stopped; sleep is enabled")
    }

    @Test func appStopReportsAFailedRestore() throws {
        let h = try CLIHarness()
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        #expect(h.dryp("app", "stop") == 1)
        #expect(h.err.last?.contains("sudo pmset -a disablesleep 0") == true)
    }

    @Test func loginToggleWritesThePref() throws {
        let h = try CLIHarness()
        #expect(h.dryp("app", "login", "off") == 0)
        #expect(h.state.prefs.openAtLogin == false)
        #expect(h.out.last == "Open at Login: off")
        #expect(h.dryp("app", "login", "on") == 0)
        #expect(h.state.prefs.openAtLogin)
        #expect(h.dryp("app", "login", "maybe") == 2)
    }
}
