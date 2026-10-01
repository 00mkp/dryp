import Foundation
import Testing
@testable import DrypCore

@Suite struct PolicyTests {
    func observe(_ state: DrypState, at now: Date = t0, applied: Applied = Applied(),
                 power: PowerInfo = .ac, available: Bool = true,
                 boot: Date = t0.addingTimeInterval(-86_400)) -> Decision {
        Policy.decide(Observation(now: now, bootTime: boot, state: state, applied: applied,
                                  power: power, nosleepAvailable: available))
    }

    @Test func nothingRequestedMeansNothingHeld() {
        let d = observe(DrypState())
        #expect(d == Decision(holdCaf: false, disableSleep: false, clear: [:], endings: [], rejection: nil))
    }

    @Test func liveSessionsAreHeld() {
        var s = DrypState()
        s.caf = session(for: .minutes(30))
        s.nosleep = session(for: nil)
        let d = observe(s, at: t0.addingTimeInterval(.minutes(10)))
        #expect(d.holdCaf && d.disableSleep)
        #expect(d.clear.isEmpty && d.endings.isEmpty)
    }

    @Test func passedDeadlineExpires() {
        var s = DrypState()
        let caf = session(for: .minutes(30))
        s.caf = caf
        let d = observe(s, at: t0.addingTimeInterval(.minutes(30)))
        #expect(!d.holdCaf)
        #expect(d.clear == [.caf: caf])
        #expect(d.endings == [Ending(mode: .caf, reason: .expired)])
    }

    @Test func deadlineBeforeBootExpiredWhileOff() {
        var s = DrypState()
        s.nosleep = session(for: .minutes(30))
        let d = observe(s, at: t0.addingTimeInterval(.hours(5)), applied: { var a = Applied(); a.nosleepSet = true; return a }(),
                        boot: t0.addingTimeInterval(.hours(4)))
        #expect(d.endings == [Ending(mode: .nosleep, reason: .expiredWhileOff)])
        #expect(!d.disableSleep)
    }

    @Test func newNosleepWithoutSetupIsRejected() {
        var s = DrypState()
        s.rev = 7
        let ns = session(for: nil)
        s.nosleep = ns
        let d = observe(s, available: false)
        #expect(d.rejection == Rejection(mode: .nosleep, reason: Policy.notSetUpReason, rev: 7))
        #expect(d.clear == [.nosleep: ns])
        #expect(!d.disableSleep)
    }

    @Test func runningNosleepSurvivesLosingSetup() {
        var s = DrypState()
        s.nosleep = session(for: nil)
        var a = Applied()
        a.nosleepSet = true
        #expect(observe(s, applied: a, available: false).disableSleep)
    }

    @Test func lowBatteryStopsRunningNosleepButNotCaf() {
        var s = DrypState()
        s.caf = session(for: nil)
        s.nosleep = session(for: nil)
        var a = Applied()
        a.nosleepSet = true
        let d = observe(s, applied: a, power: PowerInfo(onBattery: true, percent: 9))
        #expect(d.holdCaf)
        #expect(!d.disableSleep)
        #expect(d.endings == [Ending(mode: .nosleep, reason: .lowBattery(9))])
        #expect(d.rejection == nil)
    }

    @Test func lowBatteryRejectsNewNosleep() {
        var s = DrypState()
        s.rev = 3
        s.nosleep = session(for: .hours(1))
        let d = observe(s, power: PowerInfo(onBattery: true, percent: 10))
        #expect(d.rejection == Rejection(mode: .nosleep, reason: Policy.lowBatteryReason(10), rev: 3))
        #expect(d.endings.isEmpty)
    }

    @Test func lowPercentOnACIsFine() {
        var s = DrypState()
        s.nosleep = session(for: nil)
        #expect(observe(s, power: PowerInfo(onBattery: false, percent: 5)).disableSleep)
        #expect(observe(s, power: PowerInfo(onBattery: true, percent: 11)).disableSleep)
    }

    @Test func expiryWinsOverLowBattery() {
        var s = DrypState()
        s.nosleep = session(for: .minutes(30))
        var a = Applied()
        a.nosleepSet = true
        let d = observe(s, at: t0.addingTimeInterval(.hours(1)), applied: a, power: PowerInfo(onBattery: true, percent: 4))
        #expect(d.endings == [Ending(mode: .nosleep, reason: .expired)])
    }
}
