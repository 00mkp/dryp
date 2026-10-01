import Foundation

public enum Format {
    /// Minutes, rounded up so a session never shows "0m" while it still runs: "42m", "1h", "3h12m".
    public static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    /// A session length for menus: "30 min", "1 hr", "1 hr 30 min", or "no limit".
    public static func length(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "no limit" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// The right-hand side of a status row: "off", "on · no limit", "on · 42m left (until 16:52)".
    public static func status(_ session: Session?, now: Date, timeZone: TimeZone = .current) -> String {
        guard let session else { return "off" }
        guard let until = session.until else { return "on · no limit" }
        return "on · \(remaining(until.timeIntervalSince(now))) left (until \(clock(until, timeZone: timeZone)))"
    }

    /// The CLI's confirmation line.
    public static func started(_ mode: Mode, _ session: Session, timeZone: TimeZone = .current) -> String {
        guard let until = session.until else { return "\(mode.rawValue) on, no limit" }
        let length = remaining(until.timeIntervalSince(session.started))
        return "\(mode.rawValue) on for \(length) (until \(clock(until, timeZone: timeZone)))"
    }
}

/// One glyph in the menu bar.
public struct Slot: Equatable, Sendable {
    public var mode: Mode
    public var active: Bool
    public var unlimited: Bool
    /// nosleep only: a foreign disablesleep or a failed restore.
    public var alert: Bool
    public var timeText: String?

    public init(mode: Mode, active: Bool, unlimited: Bool, alert: Bool, timeText: String?) {
        self.mode = mode
        self.active = active
        self.unlimited = unlimited
        self.alert = alert
        self.timeText = timeText
    }
}

public enum MenuBarModel {
    /// Fixed slots: caf always; nosleep unless it isn't set up and nothing is wrong with sleep.
    public static func slots(state: DrypState, now: Date, foreign: Bool, restoreFailed: Bool, nosleepAvailable: Bool) -> [Slot] {
        Mode.allCases.compactMap { mode in
            let alert = mode == .nosleep && (foreign || restoreFailed)
            if mode == .nosleep && !nosleepAvailable && !alert && state.nosleep == nil { return nil }
            let s = state[mode]
            var text: String?
            if let s, state.prefs.showsTime(mode) {
                text = s.until.map { remainingText($0, now) } ?? "∞"
            }
            return Slot(mode: mode, active: s != nil, unlimited: s != nil && s?.until == nil, alert: alert, timeText: text)
        }
    }

    private static func remainingText(_ until: Date, _ now: Date) -> String {
        Format.remaining(until.timeIntervalSince(now))
    }

    public static func accessibilityLabel(_ slots: [Slot]) -> String {
        let parts = slots.map { slot -> String in
            let name = slot.mode == .caf ? "caffeinate" : "nosleep"
            var text = "\(name) \(slot.active ? "on" : "off")"
            if slot.alert { text += ", sleep needs attention" }
            return text
        }
        return "dryp: " + parts.joined(separator: ", ")
    }
}

public enum NoticeText {
    public static func ended(_ e: Ending) -> String {
        switch (e.mode, e.reason) {
        case (.caf, .expired): return "Caffeinate ended"
        case (.nosleep, .expired): return "Nosleep ended — sleep restored"
        case (_, .expiredWhileOff): return "\(e.mode.title) ended while your Mac was off"
        case (_, .lowBattery(let p)): return "\(e.mode.title) stopped: battery at \(p)%"
        }
    }

    public static func warning(_ mode: Mode) -> String { "\(mode.title) ends in 5 min" }

    public static let foreignTitle = "Sleep is disabled outside dryp"
    public static let foreignBody = "Restore it from the dryp menu, or run: \(PmsetCommand.manualRestore)"
    public static let restoreFailedTitle = "dryp couldn't restore sleep"
    public static let restoreFailedBody = "It will keep retrying. To fix it now, run: \(PmsetCommand.manualRestore)"
}
