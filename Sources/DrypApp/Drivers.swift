import DrypCore
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

enum CafError: Error, CustomStringConvertible {
    case assertionFailed(String, IOReturn)
    var description: String {
        switch self { case .assertionFailed(let type, let code): return "\(type) failed (IOReturn \(code))" }
    }
}

/// The holds `caffeinate -dimsu` takes. Released automatically if the process dies.
final class IOPMCafAssertions: PowerAssertions {
    // -d, -i, -m, -s (the last only takes effect on AC power).
    private static let types = ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep",
                                "PreventDiskIdle", "PreventSystemSleep"]
    private var ids: [IOPMAssertionID] = []

    var isHeld: Bool { !ids.isEmpty }

    func hold() throws {
        guard ids.isEmpty else { return }
        var taken: [IOPMAssertionID] = []
        for type in Self.types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "dryp caf" as CFString, &id)
            guard result == kIOReturnSuccess else {
                taken.forEach { IOPMAssertionRelease($0) }
                throw CafError.assertionFailed(type, result)
            }
            taken.append(id)
        }
        // -u: declare the user active once, which also wakes the display if it was off.
        var user = IOPMAssertionID(0)
        _ = IOPMAssertionDeclareUserActivity("dryp caf" as CFString, kIOPMUserActiveLocal, &user)
        ids = taken
    }

    func release() {
        ids.forEach { IOPMAssertionRelease($0) }
        ids = []
    }
}

/// `sudo -k -n pmset -a disablesleep 0|1`, verified by reading `pmset -g live`.
final class SudoPmset: SleepSetting {
    private let log: (String) -> Void

    init(log: @escaping (String) -> Void) { self.log = log }

    func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: Paths.sudoersFile.path)
            && Shell.run(PmsetCommand.sudo, PmsetCommand.check).status == 0
    }

    func set(disabled: Bool) -> Bool {
        let r = Shell.run(PmsetCommand.sudo, PmsetCommand.set(disabled: disabled))
        if r.status != 0 { log("sudo pmset disablesleep \(disabled ? 1 : 0) failed (\(r.status)): \(r.output)") }
        return r.status == 0
    }

    func read() -> Bool? { Shell.liveSleepDisabled() }
}

/// Battery state, with a run-loop notification on every change (no polling).
final class IOPowerSource: PowerSource {
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<IOPowerSource>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func current() -> PowerInfo {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .ac }
        // "Battery Power" is kIOPMBatteryPowerKey; the description keys below are kIOPS*Key.
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var percent: Int?
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d["Type"] as? String == "InternalBattery",
                      let current = d["Current Capacity"] as? Int,
                      let max = d["Max Capacity"] as? Int, max > 0 else { continue }
                percent = current * 100 / max
            }
        }
        return PowerInfo(onBattery: providing == "Battery Power", percent: percent)
    }
}

enum BootTime {
    static func current() -> Date {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return Date.distantPast }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
