import Foundation
import Testing
@testable import DrypCore

@Suite struct ModelsTests {
    @Test func stateRoundTripsThroughJSON() throws {
        var s = DrypState()
        s.rev = 42
        s.caf = session(for: .minutes(30))
        s.prefs.showTimeNosleep = true
        let data = try DrypJSON.encoder.encode(s)
        #expect(try DrypJSON.decoder.decode(DrypState.self, from: data) == s)
    }

    @Test func offModesAreWrittenAsExplicitNull() throws {
        let json = String(decoding: try DrypJSON.encoder.encode(DrypState()), as: UTF8.self)
        #expect(json.contains("\"nosleep\" : null"))
        #expect(json.contains("\"caf\" : null"))
    }

    @Test func missingKeysTakeDefaults() throws {
        let s = try DrypJSON.decoder.decode(DrypState.self, from: Data("{}".utf8))
        #expect(s == DrypState())
        #expect(s.prefs.openAtLogin)
        #expect(!s.prefs.showTimeCaf && !s.prefs.showTimeNosleep)
        let a = try DrypJSON.decoder.decode(Applied.self, from: Data("{}".utf8))
        #expect(a == Applied())
    }

    @Test func unknownVersionFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try DrypJSON.decoder.decode(DrypState.self, from: Data(#"{"version": 2}"#.utf8))
        }
    }

    @Test func subscriptReadsAndWritesEachMode() {
        var s = DrypState()
        s[.nosleep] = session(for: nil)
        #expect(s.nosleep?.isUnlimited == true)
        #expect(s[.caf] == nil)
        #expect(s.anyActive)
    }

    @Test func wholeSecondsDropsTheFraction() {
        let d = Date(timeIntervalSince1970: 100.75)
        #expect(d.wholeSeconds.timeIntervalSince1970 == 100)
    }

    @Test func versionConstantMatchesVersionFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        #expect(file.trimmingCharacters(in: .whitespacesAndNewlines) == DrypVersion.current)
    }
}
