import AppKit
import DrypCore

/// Draws the fixed slots: cup (caf) then laptop (nosleep). Idle = dimmed, active = full strength, no limit
/// = small orange dot, alert = orange laptop. Drawn at display time so labelColor follows the menu bar's
/// light/dark appearance.
enum IconRenderer {
    private static let symbols: [Mode: (idle: String, active: String)] = [
        .caf: ("cup.and.saucer", "cup.and.saucer.fill"),
        .nosleep: ("laptopcomputer", "laptopcomputer"),
    ]
    private static let glyphPoints: CGFloat = 14
    private static let height: CGFloat = 18
    private static let gap: CGFloat = 5
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    static func image(for slots: [Slot]) -> NSImage {
        let glyphs = slots.map { slot -> NSImage in
            let name = slot.active ? symbols[slot.mode]!.active : symbols[slot.mode]!.idle
            let config = NSImage.SymbolConfiguration(pointSize: glyphPoints, weight: .regular)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
        }
        let texts = slots.map { $0.timeText.map { NSAttributedString(string: $0, attributes: [.font: font]) } }
        var width: CGFloat = 0
        for (i, glyph) in glyphs.enumerated() {
            if i > 0 { width += gap }
            width += glyph.size.width
            if let t = texts[i] { width += 2 + ceil(t.size().width) }
            else if i == slots.count - 1, slots[i].unlimited || slots[i].alert { width += 2 }   // room for the dot's overhang
        }

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (i, slot) in slots.enumerated() {
                if i > 0 { x += gap }
                let glyph = glyphs[i]
                let color: NSColor = slot.alert ? .systemOrange : .labelColor
                let fraction: CGFloat = (slot.active || slot.alert) ? 1 : 0.45
                let rect = NSRect(x: x, y: (height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
                tinted(glyph, color).draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction)
                if slot.unlimited || slot.alert {
                    NSColor.systemOrange.setFill()
                    NSBezierPath(ovalIn: NSRect(x: rect.maxX - 4, y: rect.maxY - 4, width: 5, height: 5)).fill()
                }
                x = rect.maxX
                if let text = slot.timeText {
                    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                    let size = s.size()
                    s.draw(at: NSPoint(x: x + 2, y: (height - size.height) / 2))
                    x += 2 + ceil(size.width)
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
