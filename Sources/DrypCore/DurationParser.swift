import Foundation

public enum DurationError: Error, Equatable, CustomStringConvertible {
    case notANumber(String)
    case notWholeMinutes(String)
    case tooShort
    case tooLong

    public var description: String {
        switch self {
        case .notANumber(let s): return "'\(s)' isn't a number"
        case .notWholeMinutes(let s): return "minutes must be a whole number ('\(s)'); use -h for fractional hours"
        case .tooShort: return "duration must be at least 1 minute"
        case .tooLong: return "duration can be at most 8760 hours (one year)"
        }
    }
}

public enum DurationParser {
    public static let maxSeconds: TimeInterval = 8760 * 3600

    /// Bare numbers are whole minutes; with `hours`, decimals are allowed and rounded to the nearest minute.
    /// Returns seconds.
    public static func parse(_ text: String, hours: Bool) throws -> TimeInterval {
        let t = text.trimmingCharacters(in: .whitespaces)
        if hours {
            guard let h = Double(t), h.isFinite else { throw DurationError.notANumber(text) }
            return try checked(minutes: (h * 60).rounded())
        }
        if let m = Int(t) { return try checked(minutes: Double(m)) }
        if let d = Double(t), d.isFinite { throw DurationError.notWholeMinutes(text) }
        throw DurationError.notANumber(text)
    }

    private static func checked(minutes: Double) throws -> TimeInterval {
        guard minutes >= 1 else { throw DurationError.tooShort }
        guard minutes * 60 <= maxSeconds else { throw DurationError.tooLong }
        return minutes * 60
    }
}
