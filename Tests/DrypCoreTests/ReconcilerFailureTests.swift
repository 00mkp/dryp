import Foundation
import Testing
@testable import DrypCore

@Suite struct ReconcilerFailureTests {
    func runningNosleep() throws -> World {
        let w = try World()
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        return w
    }

    @Test func failedRestoreIsFlaggedNotifiedOnceAndRetriedWithBackoff() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 2
        try w.stop(.nosleep)
        let wake = w.reconciler.reconcile()
        #expect(w.sleep.disabled)
        #expect(w.appliedStore.read().restoreFailed)
        #expect(w.notifier.posted == [.restoreFailed])
        #expect(wake == t0.addingTimeInterval(5))

        let callsBefore = w.sleep.setCalls.count
        w.clock.advance(2)
        w.reconciler.reconcile()
        #expect(w.sleep.setCalls.count == callsBefore)          // too early to retry

        w.clock.advance(3)
        #expect(w.reconciler.reconcile() == w.clock.now.addingTimeInterval(30))   // second failure → 30 s
        #expect(w.notifier.posted == [.restoreFailed])          // still only one notice

        w.clock.advance(30)
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        let applied = w.appliedStore.read()
        #expect(!applied.restoreFailed && !applied.nosleepSet)
    }

    @Test func failingRetryAfterAgentRestartStillNotifiesOnce() throws {
        let w = try World()
        var persisted = Applied()
        persisted.nosleepSet = true
        persisted.restoreFailed = true
        try w.appliedStore.write(persisted)
        w.sleep.disabled = true
        w.sleep.ineffectiveSets = 100
        w.restartAgent()
        w.reconciler.reconcile()
        #expect(w.notifier.posted == [.restoreFailed])
        w.clock.advance(60)
        w.reconciler.reconcile()
        #expect(w.notifier.posted == [.restoreFailed])          // not again in the same process
    }

    @Test func failedRestoreIsNotForeign() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 1
        try w.stop(.nosleep)
        w.reconciler.reconcile()
        #expect(!w.reconciler.foreign)
    }

    @Test func foreignDisableIsFlaggedNotUndoneAndNotifiedOnce() throws {
        let w = try World()
        w.sleep.disabled = true
        w.reconciler.reconcile()
        w.reconciler.reconcile()
        #expect(w.reconciler.foreign)
        #expect(w.sleep.disabled)
        #expect(w.sleep.setCalls.isEmpty)
        #expect(w.notifier.posted == [.foreignSleepDisabled])
    }

    @Test func restoreRequestUndoesForeignAndClearsItself() throws {
        let w = try World()
        w.sleep.disabled = true
        w.reconciler.reconcile()
        try w.store.update { $0.restoreSleep = true }
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(!w.reconciler.foreign)
        #expect(!w.store.current().restoreSleep)
    }

    @Test func restoreRequestRetriesAFailedRestoreImmediately() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 1
        try w.stop(.nosleep)
        w.reconciler.reconcile()
        try w.store.update { $0.restoreSleep = true }
        w.clock.advance(1)                                     // before the 5 s backoff
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
        #expect(!w.appliedStore.read().restoreFailed)
    }

    @Test func restoreRequestIsIgnoredWhileNosleepIsRequested() throws {
        let w = try runningNosleep()
        try w.store.update { $0.restoreSleep = true }
        w.reconciler.reconcile()
        #expect(w.sleep.disabled)
        #expect(!w.store.current().restoreSleep)
    }

    @Test func nosleepOverForeignTakesOwnershipWithoutSudo() throws {
        let w = try World()
        w.sleep.disabled = true
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        #expect(w.sleep.setCalls.isEmpty)
        #expect(!w.reconciler.foreign)
        try w.stop(.nosleep)
        w.reconciler.reconcile()
        #expect(!w.sleep.disabled)
    }

    @Test func pmsetThatDoesNotTakeRejectsTheRequest() throws {
        let w = try World()
        w.sleep.ineffectiveSets = 1
        try w.request(.nosleep, for: nil)
        w.reconciler.reconcile()
        #expect(w.store.current().nosleep == nil)
        #expect(w.appliedStore.read().rejected?.reason.hasPrefix("pmset didn't disable sleep") == true)
    }

    @Test func shutdownClearsReleasesAndRestores() throws {
        let w = try runningNosleep()
        try w.request(.caf, for: nil)
        w.reconciler.reconcile()
        #expect(w.reconciler.shutdown())
        #expect(!w.caf.isHeld)
        #expect(!w.sleep.disabled)
        #expect(!w.store.current().anyActive)
        #expect(!w.appliedStore.read().nosleepSet)
    }

    @Test func shutdownReportsAFailedRestore() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 1
        #expect(!w.reconciler.shutdown())
        #expect(w.appliedStore.read().restoreFailed)
        #expect(w.reconciler.shutdown())                      // retry succeeds
    }

    @Test func shutdownLeavesForeignSleepAlone() throws {
        let w = try World()
        w.sleep.disabled = true
        w.reconciler.reconcile()
        #expect(w.reconciler.shutdown())
        #expect(w.sleep.disabled)
    }

    @Test func corruptStateIsQuarantinedAndOwnedSleepRestored() throws {
        let w = try runningNosleep()
        try Data("{nope".utf8).write(to: w.paths.stateFile)
        w.reconciler.reconcile()
        #expect(FileManager.default.fileExists(atPath: w.paths.badStateFile.path))
        #expect(!w.sleep.disabled)
        #expect(w.logs.contains { $0.contains("state.json.bad") })
    }

    @Test func stopWithRestoreRequestAttemptsOnceAndSchedulesFiveSeconds() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 5
        let before = w.sleep.setCalls.count
        try w.store.update { $0.nosleep = nil; $0.restoreSleep = true }
        let wake = w.reconciler.reconcile()
        #expect(w.sleep.setCalls.count == before + 1)
        #expect(wake == w.clock.now.addingTimeInterval(5))
    }

    @Test func retakingOwnershipClearsRestoreFailure() throws {
        let w = try runningNosleep()
        w.sleep.ineffectiveSets = 1
        try w.stop(.nosleep)
        w.reconciler.reconcile()
        #expect(w.appliedStore.read().restoreFailed)
        w.clock.advance(10)
        try w.request(.nosleep, for: nil)
        let wake = w.reconciler.reconcile()
        #expect(!w.appliedStore.read().restoreFailed)
        #expect(wake == nil || wake! >= w.clock.now)

        w.sleep.ineffectiveSets = 1
        try w.stop(.nosleep)
        let wake2 = w.reconciler.reconcile()
        #expect(w.notifier.posted == [.restoreFailed, .restoreFailed])
        #expect(wake2 == w.clock.now.addingTimeInterval(5))
    }
}
