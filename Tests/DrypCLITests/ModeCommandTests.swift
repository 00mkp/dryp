import Foundation
import Testing
@testable import DrypCLI
@testable import DrypCore

@Suite struct ModeCommandTests {
    @Test func cafMinutes() throws {
        let h = try CLIHarness()
        #expect(h.dryp("caf", "30") == 0)
        #expect(h.state.caf?.until == h.now.addingTimeInterval(1800))
        #expect(h.caf.isHeld)
        #expect(h.out.last?.hasPrefix("caf on for 30m (until ") == true)
    }

    @Test func dashHMeansHours() throws {
        let h = try CLIHarness()
        #expect(h.dryp("caf", "2", "-h") == 0)
        #expect(h.state.caf?.until == h.now.addingTimeInterval(7200))
        #expect(h.dryp("nosleep", "1.5", "--hours") == 0)
        #expect(h.state.nosleep?.until == h.now.addingTimeInterval(5400))
    }

    @Test func bareFormsAreUnlimited() throws {
        let h = try CLIHarness()
        #expect(h.dryp("caf") == 0)
        #expect(h.dryp("nosleep") == 0)
        #expect(h.state.caf?.isUnlimited == true)
        #expect(h.state.nosleep?.isUnlimited == true)
        #expect(h.sleep.disabled)
        #expect(h.out == ["caf on, no limit", "nosleep on, no limit"])
    }

    @Test func offStopsOneModeOnly() throws {
        let h = try CLIHarness()
        h.dryp("caf")
        h.dryp("nosleep")
        #expect(h.dryp("caf", "off") == 0)
        #expect(h.state.caf == nil)
        #expect(h.state.nosleep != nil)
        #expect(h.out.last == "caf off")
    }

    @Test func nosleepOffRestoresSleep() throws {
        let h = try CLIHarness()
        h.dryp("nosleep", "90")
        #expect(h.dryp("nosleep", "off") == 0)
        #expect(!h.sleep.disabled)
        #expect(h.out.last == "nosleep off; sleep is enabled")
    }

    @Test func nosleepOffAlsoRestoresForeignSleep() throws {
        let h = try CLIHarness()
        h.sleep.disabled = true
        #expect(h.dryp("nosleep", "off") == 0)
        #expect(!h.sleep.disabled)
    }

    @Test func offStopsBoth() throws {
        let h = try CLIHarness()
        h.dryp("caf")
        h.dryp("nosleep")
        #expect(h.dryp("off") == 0)
        #expect(!h.state.anyActive)
        #expect(!h.caf.isHeld && !h.sleep.disabled)
        #expect(h.out.last == "off; sleep is enabled")
    }

    @Test func rejectedNosleepExitsOneWithTheReason() throws {
        let h = try CLIHarness()
        h.sleep.available = false
        #expect(h.dryp("nosleep", "30") == 1)
        #expect(h.err.last == "dryp: \(Policy.notSetUpReason)")
    }

    @Test func failedRestoreExitsOneWithTheCommand() throws {
        let h = try CLIHarness()
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        #expect(h.dryp("nosleep", "off") == 1)
        #expect(h.err.last?.contains("sudo pmset -a disablesleep 0") == true)
    }

    @Test func unreadableSleepStateAfterStopExitsOne() throws {
        let h = try CLIHarness()
        h.dryp("nosleep")
        h.sleepReadOverride = .some(nil)
        #expect(h.dryp("nosleep", "off") == 1)
        #expect(h.err.last?.contains("couldn't read SleepDisabled") == true)
    }

    @Test func cafNotHeldAfterAckExitsOne() throws {
        let h = try CLIHarness()
        h.caf.ignoreHold = true
        #expect(h.dryp("caf", "30") == 1)
        #expect(h.err.last?.contains("power assertions aren't held") == true)
    }

    @Test func notRunningAgentIsStarted() throws {
        let h = try CLIHarness()
        h.agentRunning = false
        #expect(h.dryp("caf", "30") == 0)
        #expect(h.startCalls == 1)
    }

    @Test func unresponsiveAgentExitsOne() throws {
        let h = try CLIHarness()
        h.agentResponds = false
        #expect(h.dryp("caf", "30") == 1)
        #expect(h.startCalls == 1)          // one retry
        #expect(h.err.last?.contains("isn't responding") == true)
    }

    // Review Focus 2: odd durations are usage errors (exit 2) and never start anything.
    @Test(arguments: [["caf", "0"], ["caf", "1.5"], ["caf", "abc"], ["caf", "99999999"], ["nosleep", "inf"],
                      ["caf", "0.001", "-h"], ["caf", "off", "-h"], ["caf", "30", "extra"], ["bogus"], ["caf", "-h"], ["nosleep", "--hours"]])
    func usageErrorsExitTwo(_ args: [String]) throws {
        let h = try CLIHarness()
        let code = CLIEnvironment.$current.withValue(h.env) { DrypMain.run(args) }
        #expect(code == 2)
        #expect(!h.state.anyActive)
    }

    @Test func longHelpExitsZeroAndShortHIsNotHelp() throws {
        let h = try CLIHarness()
        #expect(h.dryp("--help") == 0)
        #expect(h.dryp("caf", "--help") == 0)
        #expect(h.dryp("-h") == 2)
    }
}
