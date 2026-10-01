import Foundation
@testable import DrypCore

/// A fresh fake home directory per test.
func tempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dryp-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 2026-09-30 16:00:00 UTC — every test clock starts here.
let t0 = Date(timeIntervalSince1970: 1_790_784_000)

extension TimeInterval {
    static func minutes(_ m: Double) -> TimeInterval { m * 60 }
    static func hours(_ h: Double) -> TimeInterval { h * 3600 }
}

func session(_ start: Date = t0, for length: TimeInterval?) -> Session {
    Session(started: start, until: length.map { start.addingTimeInterval($0) })
}
