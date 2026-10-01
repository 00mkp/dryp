import ArgumentParser
import DrypCore
import Foundation

enum Lifecycle {
    enum ArchiveKind: Equatable { case tarball, zip }

    static func installArguments(_ m: Manifest) -> [String] {
        ["\(m.source)/install.sh", m.nosleep ? "--nosleep" : "--no-nosleep"]
    }

    static func archiveKind(_ path: String) -> ArchiveKind? {
        let lower = path.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tarball }
        if lower.hasSuffix(".zip") { return .zip }
        return nil
    }

    /// The recorded app folder, or ~/Applications when it is empty, relative or "/".
    static func safeAppDir(_ recorded: String, env: CLIEnvironment) -> String {
        if recorded.hasPrefix("/") && recorded != "/" { return recorded }
        let fallback = env.paths.home.appendingPathComponent("Applications").path
        env.err("dryp: the recorded app folder '\(recorded)' isn't usable; using \(fallback)")
        return fallback
    }

    /// Unpacks an archive into `dest` (which the caller creates and removes) and returns the folder containing install.sh.
    static func unpack(_ archive: String, kind: ArchiveKind, into dest: URL, env: CLIEnvironment) -> URL? {
        let status = kind == .tarball
            ? env.run("/usr/bin/tar", ["-xzf", archive, "-C", dest.path], [:])
            : env.run("/usr/bin/ditto", ["-x", "-k", archive, dest.path], [:])
        guard status == 0 else { return nil }
        if FileManager.default.fileExists(atPath: dest.appendingPathComponent("install.sh").path) { return dest }
        let children = (try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)) ?? []
        return children.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("install.sh").path) }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pull the latest source, rebuild and reinstall (or install from a directory or archive).")

    @Argument(help: "A source directory or a .tar.gz/.tgz/.zip archive. Default: the recorded source.") var path: String?

    func run() throws {
        let env = CLIEnvironment.current
        guard let manifest = Manifest.read(env.paths) else {
            env.err("dryp: no install record at \(env.paths.manifestFile.path); reinstall with ./install.sh")
            throw ExitCode(1)
        }
        var source = manifest
        var unpackDir: URL?
        defer { if let unpackDir { try? FileManager.default.removeItem(at: unpackDir) } }
        var environment = ["APP_DIR": Lifecycle.safeAppDir(manifest.appDir, env: env)]

        if let path {
            let root: URL
            if let kind = Lifecycle.archiveKind(path) {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("dryp-update-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                unpackDir = dest
                guard let unpacked = Lifecycle.unpack(path, kind: kind, into: dest, env: env) else {
                    env.err("dryp: couldn't unpack \(path), or it has no install.sh")
                    throw ExitCode(1)
                }
                root = unpacked
            } else {
                root = URL(fileURLWithPath: path)
            }
            source.source = root.path
            // The given folder (or temp unpack) isn't where future updates should come from.
            environment["DRYP_SOURCE"] = manifest.source
        } else if FileManager.default.fileExists(atPath: "\(manifest.source)/.git"), !env.hasUpstream(manifest.source) {
            // A local checkout with no remote (or no tracking branch): nothing to pull, so rebuild what's there.
            env.out("==> \(manifest.source) has no upstream to pull from; reinstalling from the local source")
        } else if FileManager.default.fileExists(atPath: "\(manifest.source)/.git") {
            env.out("==> Pulling \(manifest.source)")
            guard env.run("/usr/bin/git", ["-C", manifest.source, "pull", "--ff-only"], [:]) == 0 else {
                env.err("dryp: git pull failed; nothing was reinstalled")
                throw ExitCode(1)
            }
        }

        guard FileManager.default.fileExists(atPath: "\(source.source)/install.sh") else {
            env.err("dryp: no install.sh in \(source.source); run `dryp update <path-to-dryp-source>`")
            throw ExitCode(1)
        }
        if env.run("/bin/bash", Lifecycle.installArguments(source), environment) != 0 { throw ExitCode(1) }
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop dryp, restore sleep, and remove the agent, app, CLI, state, logs and sudoers rule.")

    @Flag(help: "Remove everything even if sleep couldn't be restored.") var force = false

    func run() throws {
        let env = CLIEnvironment.current
        let fm = FileManager.default

        _ = env.agent.stop()
        var forcedPast = false
        if AppliedStore(paths: env.paths).read().nosleepSet {
            let readback = env.readSleepDisabled()
            if readback != false {
                if !force {
                    let why = readback == nil ? "SleepDisabled couldn't be read" : "couldn't restore sleep"
                    env.err("dryp: \(why), so nothing was removed. Check with `pmset -g live`, fix it with "
                            + "`\(PmsetCommand.manualRestore)` and run `dryp uninstall` again, or pass --force.")
                    throw ExitCode(1)
                }
                forcedPast = true
            }
        }

        _ = env.run("/bin/launchctl", ["bootout", Launchctl.target], [:])
        let appDir = Manifest.read(env.paths).map { Lifecycle.safeAppDir($0.appDir, env: env) }
            ?? env.paths.home.appendingPathComponent("Applications").path
        let targets = [
            env.paths.launchAgentPlist,
            URL(fileURLWithPath: appDir).appendingPathComponent("dryp.app"),
            env.paths.configDir,
            env.paths.dataDir,
            env.paths.logFile,
            env.paths.home.appendingPathComponent("Library/Logs/dryp.err.log"),
            env.paths.cliPath,
        ]
        for url in targets where fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
                env.out("removed \(url.path)")
            } catch {
                env.err("dryp: couldn't remove \(url.path): \(error.localizedDescription)")
            }
        }

        if forcedPast {
            _ = env.run("/usr/bin/sudo", ["-k", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"], [:])
            if env.readSleepDisabled() != false {
                env.err("dryp: sleep may still be disabled; run: sudo pmset -a disablesleep 0")
            }
        }

        if env.nosleepInstalled() {
            env.out("==> Removing \(Paths.sudoersFile.path) (sudo will ask for your password)")
            if env.run("/usr/bin/sudo", ["/bin/rm", "-f", Paths.sudoersFile.path], [:]) != 0 {
                env.err("dryp: couldn't remove \(Paths.sudoersFile.path); remove it with: sudo rm \(Paths.sudoersFile.path)")
                throw ExitCode(1)
            }
        }
        env.out("dryp is uninstalled.")
    }
}
