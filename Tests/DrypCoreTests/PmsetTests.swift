import Testing
@testable import DrypCore

@Suite struct PmsetTests {
    @Test func parsesSleepDisabled() {
        let live = """
            System-wide power settings:
             SleepDisabled\t\t1
            Currently in use:
             standby              1
            """
        #expect(Pmset.sleepDisabled(fromLive: live) == true)
        #expect(Pmset.sleepDisabled(fromLive: live.replacingOccurrences(of: "\t\t1", with: "\t\t0")) == false)
        #expect(Pmset.sleepDisabled(fromLive: "nothing here") == nil)
    }

    // Review Focus 1: every sudo call ignores cached credentials and never prompts.
    @Test func sudoArgumentsAlwaysIncludeKAndN() {
        #expect(PmsetCommand.set(disabled: true) == ["-k", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(PmsetCommand.set(disabled: false) == ["-k", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        #expect(PmsetCommand.check == ["-k", "-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        #expect(PmsetCommand.readLive == ["-g", "live"])
    }
}
