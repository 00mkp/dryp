import AppKit
import DrypCore

enum Alerts {
    enum RestoreChoice { case retry, quitAnyway }

    static func confirmQuit() -> Bool {
        let a = NSAlert()
        a.messageText = "Quit dryp?"
        a.informativeText = "This stops caffeinate and nosleep and lets your Mac sleep normally."
        a.addButton(withTitle: "Quit")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    static func restoreFailed() -> RestoreChoice {
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = "dryp couldn't restore sleep"
        a.informativeText = "Sleep is still disabled. To fix it by hand, run:\n\n\(PmsetCommand.manualRestore)"
        a.addButton(withTitle: "Retry")
        a.addButton(withTitle: "Quit Anyway")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn ? .retry : .quitAnyway
    }

    static func info(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    static func setUpNosleep() {
        info("Nosleep isn't set up",
             "Nosleep needs a small sudoers rule that allows only `pmset -a disablesleep 0` and `1`.\n\n"
             + "In the dryp source folder, run:\n\n./install.sh --nosleep")
    }

    /// A number field plus a Minutes/Hours picker, validated with the CLI's rules. Returns seconds, or nil on Cancel.
    static func customDuration(for mode: Mode) -> TimeInterval? {
        let a = NSAlert()
        a.messageText = "\(mode.title) for…"
        a.addButton(withTitle: "Start")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.placeholderString = "30"
        let unit = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 26), pullsDown: false)
        unit.addItems(withTitles: ["Minutes", "Hours"])
        let row = NSStackView(views: [field, unit])
        row.frame = NSRect(x: 0, y: 0, width: 200, height: 26)
        a.accessoryView = row
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while a.runModal() == .alertFirstButtonReturn {
            do {
                return try DurationParser.parse(field.stringValue, hours: unit.indexOfSelectedItem == 1)
            } catch {
                a.informativeText = "\(error)"
            }
        }
        return nil
    }
}
