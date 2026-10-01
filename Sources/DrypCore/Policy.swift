import Foundation

public struct PowerInfo: Equatable, Sendable {
    public var onBattery: Bool
    /// nil on Macs without a battery.
    public var percent: Int?

    public init(onBattery: Bool, percent: Int?) {
        self.onBattery = onBattery
        self.percent = percent
    }

    public static let ac = PowerInfo(onBattery: false, percent: nil)

    public var isLow: Bool { onBattery && (percent ?? 100) <= Policy.lowBatteryPercent }
}

public enum EndReason: Equatable, Sendable {
    case expired
    case expiredWhileOff
    case lowBattery(Int)
}

public struct Ending: Equatable, Sendable {
    public var mode: Mode
    public var reason: EndReason

    public init(mode: Mode, reason: EndReason) {
        self.mode = mode
        self.reason = reason
    }
}

public struct Observation: Sendable {
    public var now: Date
    public var bootTime: Date
    public var state: DrypState
    public var applied: Applied
    public var power: PowerInfo
    public var nosleepAvailable: Bool

    public init(now: Date, bootTime: Date, state: DrypState, applied: Applied, power: PowerInfo, nosleepAvailable: Bool) {
        self.now = now
        self.bootTime = bootTime
        self.state = state
        self.applied = applied
        self.power = power
        self.nosleepAvailable = nosleepAvailable
    }
}

public struct Decision: Equatable, Sendable {
    public var holdCaf: Bool
    public var disableSleep: Bool
    /// Modes to set to null in state.json, keyed to the exact session being cleared.
    public var clear: [Mode: Session]
    public var endings: [Ending]
    public var rejection: Rejection?

    public init(holdCaf: Bool, disableSleep: Bool, clear: [Mode: Session], endings: [Ending], rejection: Rejection?) {
        self.holdCaf = holdCaf
        self.disableSleep = disableSleep
        self.clear = clear
        self.endings = endings
        self.rejection = rejection
    }
}

/// Pure: what should be active right now, given the requests and the world.
public enum Policy {
    public static let lowBatteryPercent = 10
    public static let notSetUpReason = "nosleep isn't set up — run ./install.sh --nosleep"

    public static func lowBatteryReason(_ percent: Int) -> String {
        "battery at \(percent)% — plug in to use nosleep"
    }

    public static func decide(_ o: Observation) -> Decision {
        var d = Decision(holdCaf: false, disableSleep: false, clear: [:], endings: [], rejection: nil)

        for mode in Mode.allCases {
            guard let s = o.state[mode], let until = s.until, until <= o.now else { continue }
            d.clear[mode] = s
            d.endings.append(Ending(mode: mode, reason: until < o.bootTime ? .expiredWhileOff : .expired))
        }

        if let s = o.state.nosleep, d.clear[.nosleep] == nil {
            // "Running" means dryp already set disablesleep for it; anything else is a fresh request.
            let running = o.applied.nosleepSet
            if !running && !o.nosleepAvailable {
                d.clear[.nosleep] = s
                d.rejection = Rejection(mode: .nosleep, reason: notSetUpReason, rev: o.state.rev)
            } else if o.power.isLow {
                let percent = o.power.percent ?? 0
                d.clear[.nosleep] = s
                if running {
                    d.endings.append(Ending(mode: .nosleep, reason: .lowBattery(percent)))
                } else {
                    d.rejection = Rejection(mode: .nosleep, reason: lowBatteryReason(percent), rev: o.state.rev)
                }
            }
        }

        d.holdCaf = o.state.caf != nil && d.clear[.caf] == nil
        d.disableSleep = o.state.nosleep != nil && d.clear[.nosleep] == nil
        return d
    }
}
