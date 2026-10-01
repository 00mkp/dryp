import AppKit

/// A clickable status row laid out like mutewake's InfoRow: the name on the left and a grey detail with a
/// coloured dot pinned to the right edge, lined up with the menu's shortcut and arrow column. A normal
/// NSMenuItem title can't reach that column, so this is a custom view; it draws its own hover highlight
/// and runs its action on click, then closes the menu like an ordinary item would.
final class ToggleRow: NSView {
    // Where an ordinary title starts when the menu has a checkmark column (dryp's always does: Open at
    // Login), and the trailing gutter before key equivalents.
    static let leading: CGFloat = 25
    static let trailing: CGFloat = 14
    static let height: CGFloat = 22

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()
    private var dotColor: NSColor = .tertiaryLabelColor
    private let onClick: () -> Void
    private var enabled = true

    init(title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: Self.height))
        autoresizingMask = [.width]
        let font = NSFont.menuFont(ofSize: 0)
        titleLabel.stringValue = title
        titleLabel.font = font
        detailLabel.font = font
        detailLabel.alignment = .right
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        for v in [titleLabel, detailLabel, dotView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Updates the detail text, dot colour and enabled state, and re-lays out. Returns the width the row
    /// needs, so the menu can grow to fit it.
    @discardableResult
    func update(detail: String, dot: NSColor, enabled: Bool) -> CGFloat {
        self.enabled = enabled
        dotColor = dot
        detailLabel.stringValue = detail
        titleLabel.sizeToFit()
        detailLabel.sizeToFit()
        setAccessibilityLabel("\(titleLabel.stringValue), \(detail)")
        setAccessibilityEnabled(enabled)
        let needed = Self.leading + titleLabel.frame.width + 28 + 13 + detailLabel.frame.width + Self.trailing
        if frame.width < needed { frame.size.width = needed }
        layoutRow()
        needsDisplay = true
        return needed
    }

    private func layoutRow() {
        let y = ((Self.height - titleLabel.frame.height) / 2).rounded()
        titleLabel.frame.origin = NSPoint(x: Self.leading, y: y)
        detailLabel.frame.origin = NSPoint(x: bounds.width - Self.trailing - detailLabel.frame.width, y: y)
        dotView.frame = NSRect(x: detailLabel.frame.minX - 12, y: (Self.height - 7) / 2, width: 7, height: 7)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutRow()
    }

    private var highlighted: Bool { enabled && (enclosingMenuItem?.isHighlighted ?? false) }

    override func draw(_ dirtyRect: NSRect) {
        let on = highlighted
        if on {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        titleLabel.textColor = !enabled ? .disabledControlTextColor : (on ? .selectedMenuItemTextColor : .labelColor)
        detailLabel.textColor = on ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.85) : .secondaryLabelColor
        dotView.layer?.backgroundColor = (on && dotColor == .tertiaryLabelColor
            ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.6) : dotColor).cgColor
    }

    // The menu marks the item highlighted as the pointer moves; redraw on every move so the highlight
    // follows it (NSMenu doesn't always redraw custom views on its own).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard enabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        // Run after the menu has closed, so any alert it opens isn't stuck behind menu tracking.
        DispatchQueue.main.async(execute: onClick)
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: onClick)
        return true
    }
}
