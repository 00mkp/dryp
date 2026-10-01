import AppKit
import DrypCore

/// The menu-bar item. A plain NSMenu, like mutewake: system styling, keyboard navigation and accessibility
/// for free. Every action goes through AppDelegate, which writes state.json exactly like the CLI.
final class StatusMenu: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var liveTimer: Timer?
    private let presets: [(String, TimeInterval)] = [
        ("30 min", 1800), ("45 min", 2700), ("1 hr", 3600), ("2 hr", 7200), ("4 hr", 14_400), ("8 hr", 28_800),
    ]

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    private var slots: [Slot] {
        let r = app.reconciler!
        return MenuBarModel.slots(state: r.state, now: Date(), foreign: r.foreign,
                                  restoreFailed: r.applied.restoreFailed, nosleepAvailable: r.nosleepAvailable)
    }

    func refresh() {
        let current = slots
        item.button?.image = IconRenderer.image(for: current)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel(MenuBarModel.accessibilityLabel(current))
        // An open menu is not rebuilt (that would collapse open submenus); its status rows tick via liveTimer.
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        app.reconciler.refreshAvailability()
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        liveTimer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refreshStatusRows() }
        RunLoop.main.add(t, forMode: .eventTracking)
        liveTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    // MARK: - Building

    private func rebuild() {
        let r = app.reconciler!
        menu.removeAllItems()
        rows = [:]
        menu.addItem(statusRow(.caf))
        menu.addItem(statusRow(.nosleep))
        if r.foreign {
            menu.addItem(plain("Sleep disabled outside dryp", dot: true))
            menu.addItem(action("Restore Sleep") { [weak self] in self?.app.restoreSleep() })
        }
        if r.applied.restoreFailed {
            menu.addItem(plain("Couldn't restore sleep — \(PmsetCommand.manualRestore)", dot: true))
            menu.addItem(action("Retry") { [weak self] in self?.app.restoreSleep() })
        }
        menu.addItem(.separator())
        menu.addItem(modeSubmenu(.caf))
        if nosleepUsable {
            menu.addItem(modeSubmenu(.nosleep))
        } else {
            menu.addItem(action("Set Up Nosleep…") { Alerts.setUpNosleep() })
        }
        menu.addItem(.separator())
        let stopAll = action("Stop All", key: ".") { [weak self] in self?.app.stop([.caf, .nosleep]) }
        stopAll.isEnabled = r.state.anyActive
        menu.addItem(stopAll)
        menu.addItem(.separator())
        menu.addItem(showTimeSubmenu())
        let login = action("Open at Login") { [weak self] in
            self?.app.setPref { $0.openAtLogin.toggle() }
        }
        login.state = r.state.prefs.openAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(action("About dryp") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(action("Quit", key: "q") { [weak self] in self?.app.quitFromMenu() })
    }

    private var nosleepUsable: Bool {
        let r = app.reconciler!
        return r.nosleepAvailable || r.state.nosleep != nil
    }

    private var rows: [Mode: ToggleRow] = [:]

    private func refreshStatusRows() {
        for (mode, row) in rows { updateRow(row, mode) }
        refresh()
    }

    // MARK: - Status rows (quick toggles)

    /// What a status row shows on the right, and the colour of its dot.
    private func statusDetail(_ mode: Mode) -> (text: String, dot: NSColor) {
        let state = app.reconciler.state
        if mode == .nosleep && !nosleepUsable { return ("Not set up", .tertiaryLabelColor) }
        guard let session = state[mode] else {
            return ("Off · click for \(Format.length(state.prefs.lastLength(mode)))", .tertiaryLabelColor)
        }
        guard let until = session.until else { return ("No limit", .systemOrange) }
        return ("\(Format.remaining(until.timeIntervalSince(Date()))) left", .systemGreen)
    }

    private func updateRow(_ row: ToggleRow, _ mode: Mode) {
        let detail = statusDetail(mode)
        row.update(detail: detail.text, dot: detail.dot, enabled: mode == .caf || nosleepUsable)
    }

    /// Click while off: start the last length used. Click while on: stop.
    private func statusRow(_ mode: Mode) -> NSMenuItem {
        let row = ToggleRow(title: mode.title) { [weak self] in
            guard let self else { return }
            if self.app.reconciler.state[mode] != nil {
                self.app.stop([mode])
            } else {
                self.app.request(mode, seconds: self.app.reconciler.state.prefs.lastLength(mode))
            }
        }
        updateRow(row, mode)
        rows[mode] = row
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func plain(_ text: String, dot: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if dot {
            let title = NSMutableAttributedString(string: text)
            title.append(NSAttributedString(string: "  ●", attributes: [.foregroundColor: NSColor.systemOrange]))
            item.attributedTitle = title
        }
        return item
    }

    private func modeSubmenu(_ mode: Mode) -> NSMenuItem {
        let parent = NSMenuItem(title: mode == .caf ? "Caffeinate For" : "Nosleep For", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (title, seconds) in presets {
            sub.addItem(action(title) { [weak self] in self?.app.request(mode, seconds: seconds) })
        }
        sub.addItem(action("No Limit") { [weak self] in self?.app.request(mode, seconds: nil) })
        sub.addItem(action("Custom…") { [weak self] in
            if let seconds = Alerts.customDuration(for: mode) { self?.app.request(mode, seconds: seconds) }
        })
        sub.addItem(.separator())
        let stop = action("Stop") { [weak self] in self?.app.stop([mode]) }
        stop.isEnabled = app.reconciler.state[mode] != nil
        sub.addItem(stop)
        parent.submenu = sub
        return parent
    }

    private func showTimeSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Show Time in Menu Bar", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for mode in Mode.allCases {
            let item = action(mode.title) { [weak self] in
                self?.app.setPref { $0.setShowsTime(mode, !$0.showsTime(mode)) }
            }
            item.state = app.reconciler.state.prefs.showsTime(mode) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: - Closure-backed items

    private final class Handler: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private func action(_ title: String, key: String = "", _ run: @escaping () -> Void) -> NSMenuItem {
        let handler = Handler(run)
        let item = NSMenuItem(title: title, action: #selector(Handler.fire), keyEquivalent: key)
        item.target = handler
        item.representedObject = handler   // keeps the handler alive as long as the item
        item.isEnabled = true
        return item
    }
}
