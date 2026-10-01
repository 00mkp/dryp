import Foundation

/// A warning is sent once per (mode, deadline); extending changes the deadline, so it can warn again.
public struct WarningKey: Hashable, Sendable {
    public var mode: Mode
    public var until: Date

    public init(mode: Mode, until: Date) {
        self.mode = mode
        self.until = until
    }
}

public enum Schedule {
    public static let warningLead: TimeInterval = 5 * 60
    public static let minimumWarnedLength: TimeInterval = 10 * 60
    public static let restoreBackoff: [TimeInterval] = [5, 30, 120, 300]

    static func warningTime(_ s: Session) -> Date? {
        guard let until = s.until, until.timeIntervalSince(s.started) >= minimumWarnedLength else { return nil }
        return until.addingTimeInterval(-warningLead)
    }

    public static func dueWarnings(_ state: DrypState, now: Date, warned: Set<WarningKey>) -> [Mode] {
        Mode.allCases.filter { mode in
            guard let s = state[mode], let until = s.until, let w = warningTime(s) else { return false }
            return now >= w && now < until && !warned.contains(WarningKey(mode: mode, until: until))
        }
    }

    /// When the agent next needs to look: the earliest pending warning or deadline.
    public static func nextWake(_ state: DrypState, now: Date, warned: Set<WarningKey>) -> Date? {
        var candidates: [Date] = []
        for mode in Mode.allCases {
            guard let s = state[mode], let until = s.until else { continue }
            candidates.append(until)
            if let w = warningTime(s), w > now, !warned.contains(WarningKey(mode: mode, until: until)) {
                candidates.append(w)
            }
        }
        return candidates.min()
    }

    public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        restoreBackoff[min(max(failures, 1), restoreBackoff.count) - 1]
    }
}

public enum LoginCheck {
    /// At launch: leave quietly when Open at Login is off and nothing needs watching.
    public static func shouldExit(state: DrypState, applied: Applied, foreign: Bool, startRequested: Bool) -> Bool {
        !startRequested && !state.prefs.openAtLogin && !state.anyActive
            && !foreign && !applied.restoreFailed && !applied.nosleepSet
    }
}
