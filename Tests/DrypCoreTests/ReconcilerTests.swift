import Foundation
import Testing
@testable import DrypCore

@Suite struct ReconcilerTests {
    @Test func cafRequestHoldsAssertionsAndAcknowledges() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        #expect(w.caf.isHeld)
        let applied = w.appliedStore.read()
        #expect(applied.cafHeld)
        #expect(applied.rev == w.store.current().rev)
    }

    @Test func cafExpiryReleasesClearsAndNotifies() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.minutes(30))
        w.reconciler.reconcile()
        #expect(!w.caf.isHeld)
        #expect(w.store.current().caf == nil)
        #expect(w.notifier.posted.contains(.ended(Ending(mode: .caf, reason: .expired))))
    }

    @Test func manualStopDoesNotNotify() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        try w.stop(.caf)
        w.reconciler.reconcile()
        #expect(!w.caf.isHeld)
        #expect(w.notifier.posted.isEmpty)
    }

    @Test func nosleepDisablesAndRestoresSleep() throws {
        let w = try World()
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        #expect(w.sleep.disabled)
        #expect(w.appliedStore.read().nosleepSet)
        try w.stop(.nosleep)
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(!w.appliedStore.read().nosleepSet)
    }

    @Test func modesAreIndependent() throws {
        let w = try World()
        try w.request(.caf, for: nil)
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        try w.stop(.caf)
        w.reconciler.reconcile()
        #expect(!w.caf.isHeld)
        #expect(w.sleep.disabled)
    }

    @Test func nosleepWithoutSetupIsRejectedAndRolledBack() throws {
        let w = try World()
        w.sleep.available = false
        try w.request(.nosleep, for: .hours(1))
        let rev = w.store.current().rev
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(w.sleep.setCalls.isEmpty)
        #expect(w.store.current().nosleep == nil)
        let applied = w.appliedStore.read()
        #expect(applied.rejected == Rejection(mode: .nosleep, reason: Policy.notSetUpReason, rev: rev))
        #expect(applied.rev >= rev)
    }

    @Test func lowBatteryStopsRunningNosleep() throws {
        let w = try World()
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        w.power.info = PowerInfo(onBattery: true, percent: 9)
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(w.store.current().nosleep == nil)
        #expect(w.notifier.posted == [.ended(Ending(mode: .nosleep, reason: .lowBattery(9)))])
    }

    @Test func expiredWhileOffAfterAReboot() throws {
        let w = try World()
        try w.request(.nosleep, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.hours(3))
        w.boot = w.clock.now.addingTimeInterval(-.hours(1))
        w.restartAgent()
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(w.notifier.posted == [.ended(Ending(mode: .nosleep, reason: .expiredWhileOff))])
    }

    @Test func crashResumesUnexpiredSessions() throws {
        let w = try World()
        try w.request(.caf, for: .hours(2))
        try w.request(.nosleep, for: .hours(2))
        w.reconciler.reconcile()
        w.restartAgent()
        #expect(!w.caf.isHeld)
        w.clock.advance(.minutes(5))
        w.reconciler.reconcile()
        #expect(w.caf.isHeld)
        #expect(w.sleep.disabled)
        #expect(w.sleep.setCalls == [true])   // already disabled: no second sudo call
    }

    @Test func warningIsPostedOnceThenTheDeadlineFollows() throws {
        let w = try World()
        try w.request(.nosleep, for: .minutes(30))
        #expect(w.reconciler.reconcile() == t0.addingTimeInterval(.minutes(25)))
        w.clock.advance(.minutes(25))
        #expect(w.reconciler.reconcile() == t0.addingTimeInterval(.minutes(30)))
        w.reconciler.reconcile()
        #expect(w.notifier.posted == [.warning(.nosleep)])
    }

    @Test func extendMovesTheDeadlineAndRearmsTheWarning() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.minutes(26))
        w.reconciler.reconcile()
        w.reconciler.extend(.caf, by: .hours(1))
        #expect(w.store.current().caf?.until == t0.addingTimeInterval(.minutes(90)))
        #expect(w.reconciler.reconcile() == t0.addingTimeInterval(.minutes(85)))
    }

    @Test func extendIgnoresUnlimitedAndMissingSessions() throws {
        let w = try World()
        try w.request(.caf, for: nil)
        let before = w.store.current()
        w.reconciler.extend(.caf, by: .hours(1))
        w.reconciler.extend(.nosleep, by: .hours(1))
        #expect(w.store.current() == before)
    }

    // Review Focus 5: sleeping straight past the deadline ends it once, with no warning.
    @Test func jumpingPastTheDeadlineEndsOnceWithoutAWarning() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.hours(2))
        w.reconciler.reconcile()
        w.reconciler.reconcile()
        #expect(w.notifier.posted == [.ended(Ending(mode: .caf, reason: .expired))])
    }

    @Test func cafHoldFailureIsRejected() throws {
        let w = try World()
        w.caf.failHold = true
        try w.request(.caf, for: nil)
        w.reconciler.reconcile()
        #expect(w.store.current().caf == nil)
        #expect(w.appliedStore.read().rejected?.mode == .caf)
    }

    // Fix round 1, finding 1: a request written between the read and the clear is acted on in the same call.
    @Test func requestWrittenMidPassIsActedOnNotJustAcknowledged() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.minutes(30))
        w.power.onCurrent = { try? w.request(.nosleep, for: nil) }
        w.reconciler.reconcile()
        #expect(w.sleep.disabled)
        #expect(w.appliedStore.read().nosleepSet)
        #expect(w.appliedStore.read().rev == w.store.current().rev)
        #expect(w.store.current().caf == nil)
        #expect(w.notifier.posted == [.ended(Ending(mode: .caf, reason: .expired))])
    }

    // Fix round 1, finding 2: a failed state write neither announces the end nor busy-loops.
    @Test func failedClearDoesNotAnnounceOrSpin() throws {
        let w = try World()
        try w.request(.caf, for: .minutes(30))
        w.reconciler.reconcile()
        w.clock.advance(.minutes(31))
        let fm = FileManager.default
        let dir = w.paths.configDir.path
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir) }
        let first = w.reconciler.reconcile()
        let second = w.reconciler.reconcile()
        #expect(!w.caf.isHeld)
        #expect(w.notifier.posted.isEmpty)
        let earliest = w.clock.now.addingTimeInterval(30)
        #expect(try #require(first) >= earliest)
        #expect(try #require(second) >= earliest)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        w.reconciler.reconcile()
        #expect(w.store.current().caf == nil)
        #expect(w.notifier.posted == [.ended(Ending(mode: .caf, reason: .expired))])
    }
}
