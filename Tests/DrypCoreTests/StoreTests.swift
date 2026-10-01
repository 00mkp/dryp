import Foundation
import Testing
@testable import DrypCore

@Suite struct StoreTests {
    let paths: Paths
    let store: StateStore
    init() throws {
        paths = Paths(home: try tempHome())
        store = StateStore(paths: paths)
    }

    @Test func pathsFollowTheSpec() {
        #expect(paths.stateFile.path.hasSuffix("/.config/dryp/state.json"))
        #expect(paths.appliedFile.path.hasSuffix("/.local/share/dryp/applied.json"))
        #expect(paths.launchAgentPlist.lastPathComponent == "io.github.00mkp.dryp.plist")
        #expect(paths.cliPath.path.hasSuffix("/.local/bin/dryp"))
        #expect(Paths.sudoersFile.path == "/etc/sudoers.d/dryp")
    }

    @Test func missingFileReadsAsMissingAndDefaults() {
        #expect(store.read() == .missing)
        #expect(store.current() == DrypState())
    }

    @Test func updateWritesAndRaisesRev() throws {
        let s1 = try store.update { $0.caf = session(for: .minutes(30)) }
        #expect(s1.rev > 0)
        #expect(store.current() == s1)
        let s2 = try store.update { $0.caf = nil }
        #expect(s2.rev > s1.rev)
    }

    @Test func noOpUpdateDoesNotWrite() throws {
        let s1 = try store.update { $0.caf = session(for: nil) }
        let s2 = try store.update { _ in }
        #expect(s2.rev == s1.rev)
    }

    // Review Focus 3: rev must keep rising across a deleted state file.
    @Test func revKeepsRisingAfterTheFileIsDeleted() throws {
        let s1 = try store.update { $0.caf = session(for: nil) }
        try FileManager.default.removeItem(at: paths.stateFile)
        Thread.sleep(forTimeInterval: 0.002)  // rev falls back to wall-clock ms after a deleted file, so the two writes must land in different milliseconds
        let s2 = try store.update { $0.nosleep = session(for: nil) }
        #expect(s2.rev > s1.rev)
    }

    @Test func corruptFileIsReportedAndQuarantined() throws {
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: paths.stateFile)
        #expect(store.read() == .corrupt)
        #expect(try store.quarantineCorrupt())
        #expect(FileManager.default.fileExists(atPath: paths.badStateFile.path))
        #expect(store.read() == .missing)
        #expect(try store.quarantineCorrupt() == false)
    }

    @Test func updateOverACorruptFileQuarantinesItFirst() throws {
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: paths.stateFile)
        let s = try store.update { $0.caf = session(for: nil) }
        #expect(s.caf != nil)
        #expect(FileManager.default.fileExists(atPath: paths.badStateFile.path))
    }

    // Review Focus 4: a session replaced after the agent decided must survive its clear.
    @Test func clearOnlyRemovesUnchangedSessions() throws {
        let old = session(for: .minutes(30))
        try store.update { $0.caf = old; $0.nosleep = old }
        let replacement = session(t0.addingTimeInterval(5), for: .hours(2))
        try store.update { $0.caf = replacement }
        let after = try store.clear([.caf: old, .nosleep: old])
        #expect(after.caf == replacement)
        #expect(after.nosleep == nil)
    }

    @Test func appliedStoreRoundTripsAndDefaults() throws {
        let a = AppliedStore(paths: paths)
        #expect(a.read() == Applied())
        var x = Applied()
        x.rev = 9
        x.nosleepSet = true
        x.rejected = Rejection(mode: .nosleep, reason: "r", rev: 9)
        try a.write(x)
        #expect(a.read() == x)
    }

    @Test func startMarkerIsConsumedOnce() {
        #expect(!StartMarker.consume(paths))
        StartMarker.touch(paths)
        #expect(StartMarker.consume(paths))
        #expect(!StartMarker.consume(paths))
    }

    @Test func manifestParses() {
        let m = Manifest.parse("""
            version=0.1.0
            source=/Users/me/src/dryp
            app_dir=/Users/me/Applications
            nosleep=yes
            installed=2026-09-30T16:00:00Z
            """)
        #expect(m == Manifest(version: "0.1.0", source: "/Users/me/src/dryp", appDir: "/Users/me/Applications", nosleep: true))
        #expect(Manifest.parse("version=0.1.0") == nil)
    }
}
