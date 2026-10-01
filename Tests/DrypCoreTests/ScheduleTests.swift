import Foundation
import Testing
@testable import DrypCore

@Suite struct ScheduleTests {
    func state(caf: Session? = nil, nosleep: Session? = nil) -> DrypState {
        var s = DrypState()
        s.caf = caf
        s.nosleep = nosleep
        return s
    }

    @Test func warningIsDueInTheLastFiveMinutes() {
        let s = state(caf: session(for: .minutes(30)))
        #expect(Schedule.dueWarnings(s, now: t0.addingTimeInterval(.minutes(24)), warned: []).isEmpty)
        #expect(Schedule.dueWarnings(s, now: t0.addingTimeInterval(.minutes(25)), warned: []) == [.caf])
        #expect(Schedule.dueWarnings(s, now: t0.addingTimeInterval(.minutes(30)), warned: []).isEmpty)
    }

    @Test func warnedSessionsAreNotWarnedAgain() {
        let caf = session(for: .minutes(30))
        let warned: Set = [WarningKey(mode: .caf, until: caf.until!)]
        #expect(Schedule.dueWarnings(state(caf: caf), now: t0.addingTimeInterval(.minutes(26)), warned: warned).isEmpty)
    }

    @Test func extendedSessionIsWarnedAgain() {
        let caf = session(for: .minutes(30))
        let warned: Set = [WarningKey(mode: .caf, until: caf.until!)]
        let extended = Session(started: caf.started, until: caf.until!.addingTimeInterval(.hours(1)))
        #expect(Schedule.dueWarnings(state(caf: extended), now: t0.addingTimeInterval(.minutes(86)), warned: warned) == [.caf])
    }

    @Test func shortAndUnlimitedSessionsAreNeverWarned() {
        let s = state(caf: session(for: .minutes(9)), nosleep: session(for: nil))
        #expect(Schedule.dueWarnings(s, now: t0.addingTimeInterval(.minutes(6)), warned: []).isEmpty)
        #expect(Schedule.nextWake(s, now: t0, warned: []) == t0.addingTimeInterval(.minutes(9)))
    }

    @Test func nextWakeIsTheEarliestWarningOrDeadline() {
        let s = state(caf: session(for: .hours(2)), nosleep: session(for: .minutes(30)))
        #expect(Schedule.nextWake(s, now: t0, warned: []) == t0.addingTimeInterval(.minutes(25)))
        let warned: Set = [WarningKey(mode: .nosleep, until: t0.addingTimeInterval(.minutes(30)))]
        #expect(Schedule.nextWake(s, now: t0.addingTimeInterval(.minutes(26)), warned: warned) == t0.addingTimeInterval(.minutes(30)))
    }

    @Test func nothingTimedMeansNoWake() {
        #expect(Schedule.nextWake(state(nosleep: session(for: nil)), now: t0, warned: []) == nil)
    }

    @Test func backoffFollowsTheSpec() {
        #expect([1, 2, 3, 4, 5, 9].map { Schedule.retryDelay(afterFailures: $0) } == [5, 30, 120, 300, 300, 300])
    }

    @Test func loginCheckExitsOnlyWhenNothingNeedsTheAgent() {
        var s = DrypState()
        s.prefs.openAtLogin = false
        #expect(LoginCheck.shouldExit(state: s, applied: Applied(), foreign: false, startRequested: false))
        #expect(!LoginCheck.shouldExit(state: s, applied: Applied(), foreign: false, startRequested: true))
        #expect(!LoginCheck.shouldExit(state: s, applied: Applied(), foreign: true, startRequested: false))
        var failed = Applied()
        failed.restoreFailed = true
        #expect(!LoginCheck.shouldExit(state: s, applied: failed, foreign: false, startRequested: false))
        var owned = Applied()
        owned.nosleepSet = true
        #expect(!LoginCheck.shouldExit(state: s, applied: owned, foreign: false, startRequested: false))
        var active = s
        active.caf = session(for: nil)
        #expect(!LoginCheck.shouldExit(state: active, applied: Applied(), foreign: false, startRequested: false))
        #expect(!LoginCheck.shouldExit(state: DrypState(), applied: Applied(), foreign: false, startRequested: false))
    }
}
