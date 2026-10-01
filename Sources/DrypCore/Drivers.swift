import Foundation

/// The caf hold (IOPMAssertion in the app; a fake in tests).
public protocol PowerAssertions: AnyObject {
    var isHeld: Bool { get }
    func hold() throws
    func release()
}

/// `sudo -k -n pmset -a disablesleep 0|1` and `pmset -g live`.
public protocol SleepSetting: AnyObject {
    /// Whether the NOPASSWD rule is installed and works.
    func isAvailable() -> Bool
    /// Runs the command; true if it exited 0. The caller verifies with `read()`.
    @discardableResult func set(disabled: Bool) -> Bool
    /// The live SleepDisabled value; nil if it couldn't be read.
    func read() -> Bool?
}

public protocol PowerSource: AnyObject {
    func current() -> PowerInfo
}

public enum Notice: Equatable, Sendable {
    case ended(Ending)
    case warning(Mode)
    case foreignSleepDisabled
    case restoreFailed
}

public protocol Notifier: AnyObject {
    func post(_ notice: Notice)
}
