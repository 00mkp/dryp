import Foundation

/// Every file dryp touches, relative to one home directory (tests use a fake home).
public struct Paths: Sendable {
    public static let label = "io.github.00mkp.dryp"
    public static let sudoersFile = URL(fileURLWithPath: "/etc/sudoers.d/dryp")

    public var home: URL

    public init(home: URL) { self.home = home }

    public static var live: Paths { Paths(home: FileManager.default.homeDirectoryForCurrentUser) }

    public var configDir: URL { home.appendingPathComponent(".config/dryp", isDirectory: true) }
    public var stateFile: URL { configDir.appendingPathComponent("state.json") }
    public var lockFile: URL { configDir.appendingPathComponent("state.lock") }
    public var badStateFile: URL { configDir.appendingPathComponent("state.json.bad") }

    public var dataDir: URL { home.appendingPathComponent(".local/share/dryp", isDirectory: true) }
    public var appliedFile: URL { dataDir.appendingPathComponent("applied.json") }
    public var manifestFile: URL { dataDir.appendingPathComponent("manifest") }
    public var startMarker: URL { dataDir.appendingPathComponent("start") }

    public var logFile: URL { home.appendingPathComponent("Library/Logs/dryp.log") }
    public var launchAgentPlist: URL { home.appendingPathComponent("Library/LaunchAgents/\(Paths.label).plist") }
    public var cliPath: URL { home.appendingPathComponent(".local/bin/dryp") }
}
