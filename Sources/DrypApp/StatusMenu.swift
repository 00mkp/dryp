import AppKit

/// Replaced by the real menu in Task 15.
final class StatusMenu {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    init(app: AppDelegate) { item.button?.title = "dryp" }
    func refresh() {}
}
