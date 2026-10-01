import AppKit

/// dryp's app icon (Finder, Spotlight, System Settings, the About panel): the white filled cup on a warm
/// coffee-brown tile, on the macOS icon grid — an 824/1024 rounded square, centred, with room for its shadow.
/// Drawn in code (like peel) so no binary icon is checked in.
public enum DrypIcon {
    public static func appIconPNG(pixels px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px) / 1024
        let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.shadowBlurRadius = 24 * s
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Coffee brown, lighter (crema) at the top.
        NSGradient(starting: NSColor(srgbRed: 0.71, green: 0.47, blue: 0.29, alpha: 1),
                   ending: NSColor(srgbRed: 0.36, green: 0.21, blue: 0.12, alpha: 1))!
            .draw(in: shape, angle: -90)

        drawCup(in: tile.insetBy(dx: tile.width * 0.18, dy: tile.height * 0.18))

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// The same SF Symbol the menu bar uses, rendered white and centred.
    static func drawCup(in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: rect.height * 0.8, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = symbol.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let origin = NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawn))
    }

    /// Writes the .iconset folder `iconutil -c icns` turns into the app's icon: each size at 1x and 2x.
    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            try appIconPNG(pixels: size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
            try appIconPNG(pixels: size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
    }
}
