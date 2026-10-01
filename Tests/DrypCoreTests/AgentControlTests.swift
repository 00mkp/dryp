import Foundation
import Testing
@testable import DrypCore

@Suite struct AgentControlTests {
    @Test func pidParsesFromLaunchctlPrint() {
        let running = """
            gui/501/io.github.00mkp.dryp = {
            \tactive count = 1
            \tstate = running
            \tpid = 4411
            }
            """
        #expect(Launchctl.pid(fromPrint: running) == 4411)
        #expect(Launchctl.pid(fromPrint: "gui/501/io.github.00mkp.dryp = {\n\tstate = not running\n}") == nil)
    }

    @Test func targetNamesTheLabelInTheGUIDomain() {
        #expect(Launchctl.target == "gui/\(getuid())/io.github.00mkp.dryp")
    }

    @Test func shellCapturesOutputAndStatus() {
        let r = Shell.run("/bin/sh", ["-c", "echo hi; exit 3"])
        #expect(r == Shell.Result(status: 3, output: "hi\n"))
    }

    @Test func shellTimesOut() {
        let r = Shell.run("/bin/sleep", ["5"], timeout: 0.3)
        #expect(r.status == 124)
    }

    @Test func missingExecutableIs127() {
        #expect(Shell.run("/no/such/tool", []).status == 127)
    }

    @Test func fileLogAppendsTimestampedLines() throws {
        let url = try tempHome().appendingPathComponent("Library/Logs/dryp.log")
        let log = FileLog(url: url, now: { t0 })
        log.write("one")
        log.write("two")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("] one"))
        #expect(lines[0].hasPrefix("[2026-"))
    }
}
