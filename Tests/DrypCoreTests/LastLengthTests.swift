import Foundation
import Testing
@testable import DrypCore

@Suite struct LastLengthTests {
    @Test func defaultsToOneHourForBothModes() {
        let p = Prefs()
        #expect(p.lastLength(.caf) == 3600)
        #expect(p.lastLength(.nosleep) == 3600)
    }

    @Test func beginRecordsTheSessionAndTheLength() {
        var s = DrypState()
        s.begin(.nosleep, at: t0, length: 7200)
        #expect(s.nosleep == Session(started: t0, until: t0.addingTimeInterval(7200)))
        #expect(s.prefs.lastLength(.nosleep) == 7200)
        #expect(s.prefs.lastLength(.caf) == 3600)
    }

    @Test func noLimitIsRememberedAsNil() {
        var s = DrypState()
        s.begin(.caf, at: t0, length: nil)
        #expect(s.caf?.isUnlimited == true)
        #expect(s.prefs.lastLength(.caf) == nil)
    }

    @Test func lastLengthRoundTripsAndOldFilesLoad() throws {
        var s = DrypState()
        s.begin(.caf, at: t0, length: 2700)
        s.begin(.nosleep, at: t0, length: nil)
        let back = try DrypJSON.decoder.decode(DrypState.self, from: DrypJSON.encoder.encode(s))
        #expect(back.prefs.lastLength(.caf) == 2700)
        #expect(back.prefs.lastLength(.nosleep) == nil)
        let old = try DrypJSON.decoder.decode(Prefs.self, from: Data(#"{"openAtLogin": false}"#.utf8))
        #expect(old.lastLength(.caf) == 3600)
    }

    @Test(arguments: [(1800.0, "30 min"), (2700.0, "45 min"), (3600.0, "1 hr"), (5400.0, "1 hr 30 min"),
                      (7200.0, "2 hr"), (60.0, "1 min")])
    func lengthLabels(_ seconds: Double, _ text: String) {
        #expect(Format.length(seconds) == text)
    }

    @Test func noLimitLabel() {
        #expect(Format.length(nil) == "no limit")
    }
}
