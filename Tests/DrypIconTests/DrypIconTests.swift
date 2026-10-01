import AppKit
import Foundation
import Testing
@testable import DrypIcon

@Suite struct DrypIconTests {
    @Test func pngHasTheRequestedSize() throws {
        let rep = try #require(NSBitmapImageRep(data: DrypIcon.appIconPNG(pixels: 64)))
        #expect(rep.pixelsWide == 64 && rep.pixelsHigh == 64)
    }

    @Test func tileIsOpaqueInTheMiddleAndClearInTheCorner() throws {
        let rep = try #require(NSBitmapImageRep(data: DrypIcon.appIconPNG(pixels: 256)))
        #expect((rep.colorAt(x: 128, y: 200)?.alphaComponent ?? 0) > 0.99)
        #expect((rep.colorAt(x: 2, y: 2)?.alphaComponent ?? 1) < 0.05)
    }

    @Test func glyphIsDrawnInWhite() throws {
        // Some pixel in the central region must be near-white (the cup), proving the glyph rendered.
        let rep = try #require(NSBitmapImageRep(data: DrypIcon.appIconPNG(pixels: 256)))
        var white = 0
        for x in stride(from: 64, to: 192, by: 2) {
            for y in stride(from: 64, to: 192, by: 2) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.sRGB),
                   c.redComponent > 0.9, c.greenComponent > 0.9, c.blueComponent > 0.9 { white += 1 }
            }
        }
        #expect(white > 100)
    }

    @Test func iconsetHasEveryRequiredSize() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dryp-\(UUID().uuidString).iconset")
        try DrypIcon.writeIconset(to: dir)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        for size in [16, 32, 128, 256, 512] {
            #expect(names.contains("icon_\(size)x\(size).png"))
            #expect(names.contains("icon_\(size)x\(size)@2x.png"))
        }
    }
}
