import Foundation
import Testing
@testable import DrypCLI
@testable import DrypCore

@Suite struct LifecycleTests {
    func writeManifest(_ h: CLIHarness, source: String, nosleep: Bool = true) throws {
        try FileManager.default.createDirectory(at: h.paths.dataDir, withIntermediateDirectories: true)
        try """
            version=0.1.0
            source=\(source)
            app_dir=\(h.paths.home.path)/Applications
            nosleep=\(nosleep ? "yes" : "no")
            installed=2026-09-30T16:00:00Z
            """.write(to: h.paths.manifestFile, atomically: true, encoding: .utf8)
    }

    @Test func installArgumentsKeepTheNosleepChoice() {
        #expect(Lifecycle.installArguments(Manifest(version: "", source: "/s", appDir: "/a", nosleep: true)) == ["/s/install.sh", "--nosleep"])
        #expect(Lifecycle.installArguments(Manifest(version: "", source: "/s", appDir: "/a", nosleep: false)) == ["/s/install.sh", "--no-nosleep"])
    }

    @Test func archiveKinds() {
        #expect(Lifecycle.archiveKind("/x/dryp-0.2.0.tar.gz") == .tarball)
        #expect(Lifecycle.archiveKind("/x/dryp.tgz") == .tarball)
        #expect(Lifecycle.archiveKind("/x/dryp.zip") == .zip)
        #expect(Lifecycle.archiveKind("/x/dryp") == nil)
    }

    @Test func updateWithoutAManifestFails() throws {
        let h = try CLIHarness()
        #expect(h.dryp("update") == 1)
        #expect(h.err.last?.contains("no install record") == true)
    }

    @Test func updatePullsThenRunsTheInstallerWithTheRecordedChoice() throws {
        let h = try CLIHarness()
        let source = h.paths.home.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".git"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.appendingPathComponent("install.sh").path, contents: Data())
        try writeManifest(h, source: source.path, nosleep: false)
        #expect(h.dryp("update") == 0)
        #expect(h.runs.map { $0.0 } == ["/usr/bin/git", "/bin/bash"])
        #expect(h.runs[0].1 == ["-C", source.path, "pull", "--ff-only"])
        #expect(h.runs[1].1 == ["\(source.path)/install.sh", "--no-nosleep"])
        #expect(h.runs[1].2["APP_DIR"] == "\(h.paths.home.path)/Applications")
    }

    @Test func updateFromADirectoryRecordsTheOldSource() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/old/src")
        let other = h.paths.home.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.appendingPathComponent("install.sh").path, contents: Data())
        #expect(h.dryp("update", other.path) == 0)
        #expect(h.runs.count == 1)
        #expect(h.runs[0].1 == ["\(other.path)/install.sh", "--nosleep"])
        #expect(h.runs[0].2["DRYP_SOURCE"] == "/old/src")
    }

    @Test func failedPullStopsTheUpdate() throws {
        let h = try CLIHarness()
        let source = h.paths.home.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: source.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try writeManifest(h, source: source.path)
        h.runStatus = 3
        #expect(h.dryp("update") == 1)
        #expect(h.runs.count == 1)
    }

    @Test func uninstallStopsTheAgentRemovesFilesAndTheSudoersRule() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/s")
        h.dryp("nosleep")
        let app = h.paths.home.appendingPathComponent("Applications/dryp.app")
        for url in [app, h.paths.launchAgentPlist, h.paths.cliPath, h.paths.logFile] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        #expect(h.dryp("uninstall") == 0)
        #expect(h.stopCalls == 1)
        #expect(!h.sleep.disabled)
        for url in [app, h.paths.launchAgentPlist, h.paths.cliPath, h.paths.logFile, h.paths.configDir, h.paths.dataDir] {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.path) should be gone")
        }
        #expect(h.runs.contains { $0.0 == "/bin/launchctl" && $0.1.first == "bootout" })
        #expect(h.runs.contains { $0.0 == "/usr/bin/sudo" && $0.1 == ["/bin/rm", "-f", "/etc/sudoers.d/dryp"] })
    }

    @Test func uninstallRefusesWhileSleepCannotBeRestored() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/s")
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        try FileManager.default.createDirectory(at: h.paths.launchAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: h.paths.launchAgentPlist.path, contents: Data())
        #expect(h.dryp("uninstall") == 1)
        #expect(FileManager.default.fileExists(atPath: h.paths.manifestFile.path))
        #expect(h.err.last?.contains("--force") == true)
        #expect(!h.runs.contains { $0.0 == "/bin/launchctl" || $0.0 == "/usr/bin/sudo" })
        #expect(FileManager.default.fileExists(atPath: h.paths.launchAgentPlist.path))
    }

    @Test func uninstallRefusesWhenSleepCannotBeRead() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/s")
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        h.sleepReadOverride = .some(nil)
        #expect(h.dryp("uninstall") == 1)
        #expect(h.err.last?.contains("couldn't be read") == true)
        #expect(FileManager.default.fileExists(atPath: h.paths.manifestFile.path))
    }

    @Test func forceRestoresBeforeRemovingTheSudoersRuleAndWarns() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/s")
        h.dryp("nosleep")
        h.sleep.ineffectiveSets = 5
        #expect(h.dryp("uninstall", "--force") == 0)
        let tools = h.runs.map { $0.1.contains("/usr/bin/pmset") ? "pmset" : $0.0 }
        let pmset = try #require(tools.firstIndex(of: "pmset"))
        let rm = try #require(h.runs.firstIndex { $0.1.contains("/bin/rm") })
        #expect(pmset < rm)
        #expect(h.runs[pmset].1 == ["-k", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        #expect(h.err.contains("dryp: sleep may still be disabled; run: sudo pmset -a disablesleep 0"))
    }

    @Test func anUnusableRecordedAppFolderFallsBackToHomeApplications() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/s")
        let text = try String(contentsOf: h.paths.manifestFile).replacingOccurrences(
            of: "app_dir=\(h.paths.home.path)/Applications", with: "app_dir=")
        try text.write(to: h.paths.manifestFile, atomically: true, encoding: .utf8)
        let app = h.paths.home.appendingPathComponent("Applications/dryp.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        #expect(h.dryp("uninstall") == 0)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        #expect(h.err.contains { $0.contains("isn't usable") })
    }

    @Test func updateWithoutInstallShFails() throws {
        let h = try CLIHarness()
        try writeManifest(h, source: "/nonexistent/src")
        #expect(h.dryp("update") == 1)
        #expect(h.runs.isEmpty)
        #expect(h.err.last?.contains("no install.sh") == true)
    }
}
