import Foundation
import Testing
@testable import DrypCore

@Suite struct FormatTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test(arguments: [(59.0, "1m"), (60.0, "1m"), (2519.0, "42m"), (3600.0, "1h"), (11_520.0, "3h12m"), (-5.0, "0m")])
    func remaining(_ seconds: Double, _ text: String) {
        #expect(Format.remaining(seconds) == text)
    }

    @Test func statusLines() {
        #expect(Format.status(nil, now: t0, timeZone: utc) == "off")
        #expect(Format.status(session(for: nil), now: t0, timeZone: utc) == "on · no limit")
        #expect(Format.status(session(for: .minutes(52)), now: t0.addingTimeInterval(.minutes(10)), timeZone: utc)
            == "on · 42m left (until 16:52)")
    }

    @Test func startedLines() {
        #expect(Format.started(.caf, session(for: nil), timeZone: utc) == "caf on, no limit")
        #expect(Format.started(.nosleep, session(for: .minutes(90)), timeZone: utc) == "nosleep on for 1h30m (until 17:30)")
    }

    @Test func slotsShowBothModesWithDotsAndOptionalTimes() {
        var s = DrypState()
        s.caf = session(for: .minutes(42))
        s.nosleep = session(for: nil)
        s.prefs.showTimeCaf = true
        let slots = MenuBarModel.slots(state: s, now: t0, foreign: false, restoreFailed: false, nosleepAvailable: true)
        #expect(slots == [
            Slot(mode: .caf, active: true, unlimited: false, alert: false, timeText: "42m"),
            Slot(mode: .nosleep, active: true, unlimited: true, alert: false, timeText: nil),
        ])
        s.prefs.showTimeNosleep = true
        #expect(MenuBarModel.slots(state: s, now: t0, foreign: false, restoreFailed: false, nosleepAvailable: true)[1].timeText == "∞")
    }

    @Test func idleSlotsAreFixed() {
        let slots = MenuBarModel.slots(state: DrypState(), now: t0, foreign: false, restoreFailed: false, nosleepAvailable: true)
        #expect(slots.map(\.mode) == [.caf, .nosleep])
        #expect(slots.allSatisfy { !$0.active && !$0.alert })
    }

    @Test func nosleepSlotHiddenWhenNotSetUpUnlessSomethingIsWrong() {
        let s = DrypState()
        #expect(MenuBarModel.slots(state: s, now: t0, foreign: false, restoreFailed: false, nosleepAvailable: false).map(\.mode) == [.caf])
        let alerted = MenuBarModel.slots(state: s, now: t0, foreign: true, restoreFailed: false, nosleepAvailable: false)
        #expect(alerted.last == Slot(mode: .nosleep, active: false, unlimited: false, alert: true, timeText: nil))
    }

    @Test func accessibilityLabelSpellsOutState() {
        var s = DrypState()
        s.caf = session(for: .minutes(42))
        let slots = MenuBarModel.slots(state: s, now: t0, foreign: false, restoreFailed: false, nosleepAvailable: true)
        #expect(MenuBarModel.accessibilityLabel(slots) == "dryp: caffeinate on, nosleep off")
    }

    @Test func noticeText() {
        #expect(NoticeText.ended(Ending(mode: .nosleep, reason: .expired)) == "Nosleep ended — sleep restored")
        #expect(NoticeText.ended(Ending(mode: .caf, reason: .expired)) == "Caffeinate ended")
        #expect(NoticeText.ended(Ending(mode: .nosleep, reason: .expiredWhileOff)) == "Nosleep ended while your Mac was off")
        #expect(NoticeText.ended(Ending(mode: .nosleep, reason: .lowBattery(9))) == "Nosleep stopped: battery at 9%")
        #expect(NoticeText.warning(.caf) == "Caffeinate ends in 5 min")
    }
}
