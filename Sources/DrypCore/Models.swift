import Foundation

public enum Mode: String, Codable, CaseIterable, Sendable {
    case caf, nosleep

    /// How the menu and notifications name the mode.
    public var title: String { self == .caf ? "Caffeinate" : "Nosleep" }
}

/// One running mode. `until == nil` means no limit.
public struct Session: Codable, Equatable, Sendable {
    public var started: Date
    public var until: Date?

    public init(started: Date, until: Date?) {
        self.started = started
        self.until = until
    }

    public var isUnlimited: Bool { until == nil }
}

public struct Prefs: Codable, Equatable, Sendable {
    public var showTimeCaf = false
    public var showTimeNosleep = false
    public var openAtLogin = true

    public init() {}

    public func showsTime(_ mode: Mode) -> Bool { mode == .caf ? showTimeCaf : showTimeNosleep }

    public mutating func setShowsTime(_ mode: Mode, _ on: Bool) {
        if mode == .caf { showTimeCaf = on } else { showTimeNosleep = on }
    }

    enum CodingKeys: String, CodingKey { case showTimeCaf, showTimeNosleep, openAtLogin }

    // Every key is optional on disk so older or hand-edited files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showTimeCaf = try c.decodeIfPresent(Bool.self, forKey: .showTimeCaf) ?? false
        showTimeNosleep = try c.decodeIfPresent(Bool.self, forKey: .showTimeNosleep) ?? false
        openAtLogin = try c.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? true
    }
}

/// The requests file, `~/.config/dryp/state.json`. Written by the CLI and the menu; read by the agent.
public struct DrypState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = DrypState.currentVersion
    public var rev = 0
    public var caf: Session?
    public var nosleep: Session?
    /// One-shot request: set disablesleep 0 even if dryp didn't set it. The agent clears it.
    public var restoreSleep = false
    public var prefs = Prefs()

    public init() {}

    public subscript(mode: Mode) -> Session? {
        get { mode == .caf ? caf : nosleep }
        set { if mode == .caf { caf = newValue } else { nosleep = newValue } }
    }

    public var anyActive: Bool { caf != nil || nosleep != nil }

    enum CodingKeys: String, CodingKey { case version, rev, caf, nosleep, restoreSleep, prefs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? DrypState.currentVersion
        guard version == DrypState.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: c, debugDescription: "unsupported state version \(version)")
        }
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        caf = try c.decodeIfPresent(Session.self, forKey: .caf)
        nosleep = try c.decodeIfPresent(Session.self, forKey: .nosleep)
        restoreSleep = try c.decodeIfPresent(Bool.self, forKey: .restoreSleep) ?? false
        prefs = try c.decodeIfPresent(Prefs.self, forKey: .prefs) ?? Prefs()
    }

    // Explicit so that an off mode is written as `null` rather than omitted.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(rev, forKey: .rev)
        try c.encode(caf, forKey: .caf)
        try c.encode(nosleep, forKey: .nosleep)
        try c.encode(restoreSleep, forKey: .restoreSleep)
        try c.encode(prefs, forKey: .prefs)
    }
}

public struct Rejection: Codable, Equatable, Sendable {
    public var mode: Mode
    public var reason: String
    /// The state revision the agent was looking at when it refused.
    public var rev: Int

    public init(mode: Mode, reason: String, rev: Int) {
        self.mode = mode
        self.reason = reason
        self.rev = rev
    }
}

/// The agent's record of what it actually did, `~/.local/share/dryp/applied.json`. Agent-only writer.
public struct Applied: Codable, Equatable, Sendable {
    public var rev = 0
    public var cafHeld = false
    /// True when dryp itself set disablesleep 1 — what makes a disabled sleep "owned" rather than foreign.
    public var nosleepSet = false
    public var rejected: Rejection?
    public var restoreFailed = false

    public init() {}

    enum CodingKeys: String, CodingKey { case rev, cafHeld, nosleepSet, rejected, restoreFailed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        cafHeld = try c.decodeIfPresent(Bool.self, forKey: .cafHeld) ?? false
        nosleepSet = try c.decodeIfPresent(Bool.self, forKey: .nosleepSet) ?? false
        rejected = try c.decodeIfPresent(Rejection.self, forKey: .rejected)
        restoreFailed = try c.decodeIfPresent(Bool.self, forKey: .restoreFailed) ?? false
    }
}

public enum DrypJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension Date {
    /// ISO-8601 on disk has no fractional seconds; build sessions from this so they compare equal after a round trip.
    public var wholeSeconds: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
}
