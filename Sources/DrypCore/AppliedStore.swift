import Foundation

/// The agent's record of what it did. Only the agent writes it, so no lock is needed.
public struct AppliedStore: Sendable {
    public let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public func read() -> Applied {
        guard let data = try? Data(contentsOf: paths.appliedFile),
              let applied = try? DrypJSON.decoder.decode(Applied.self, from: data) else { return Applied() }
        return applied
    }

    public func write(_ applied: Applied) throws {
        try FileManager.default.createDirectory(at: paths.dataDir, withIntermediateDirectories: true)
        try DrypJSON.encoder.encode(applied).write(to: paths.appliedFile, options: .atomic)
    }
}

/// "Stay in the menu bar this launch": written by `dryp app start`, the Finder handoff and install.sh;
/// consumed by the agent's login check.
public enum StartMarker {
    public static func touch(_ paths: Paths) {
        try? FileManager.default.createDirectory(at: paths.dataDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.startMarker.path, contents: Data())
    }

    public static func consume(_ paths: Paths) -> Bool {
        (try? FileManager.default.removeItem(at: paths.startMarker)) != nil
    }
}

/// `~/.local/share/dryp/manifest`, written by install.sh: key=value lines.
public struct Manifest: Equatable, Sendable {
    public var version: String
    public var source: String
    public var appDir: String
    public var nosleep: Bool

    public init(version: String, source: String, appDir: String, nosleep: Bool) {
        self.version = version
        self.source = source
        self.appDir = appDir
        self.nosleep = nosleep
    }

    public static func parse(_ text: String) -> Manifest? {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        guard let version = values["version"], let source = values["source"],
              let appDir = values["app_dir"], let nosleep = values["nosleep"] else { return nil }
        return Manifest(version: version, source: source, appDir: appDir, nosleep: nosleep == "yes")
    }

    public static func read(_ paths: Paths) -> Manifest? {
        guard let text = try? String(contentsOf: paths.manifestFile, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
