import Foundation

public enum Pmset {
    /// Reads `SleepDisabled` from `pmset -g live`; nil if the line is missing.
    public static func sleepDisabled(fromLive output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count >= 2, fields[0] == "SleepDisabled" { return fields[1] == "1" }
        }
        return nil
    }
}

/// Argument lists for the only privileged commands dryp runs. `-k` ignores cached sudo credentials, so a
/// recent interactive `sudo` can't make a missing NOPASSWD rule look like it works; `-n` never prompts.
public enum PmsetCommand {
    public static let sudo = "/usr/bin/sudo"
    public static let pmset = "/usr/bin/pmset"
    public static let manualRestore = "sudo pmset -a disablesleep 0"

    public static func set(disabled: Bool) -> [String] {
        ["-k", "-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]
    }

    public static let check = ["-k", "-n", "-l", pmset, "-a", "disablesleep", "0"]
    public static let readLive = ["-g", "live"]
}
