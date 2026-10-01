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
        menu.addItem(statusRow(.caf))
        if r.nosleepAvailable || r.state.nosleep != nil {
            menu.addItem(statusRow(.nosleep))
        } else {
            menu.addItem(plain("Nosleep: not set up"))
        }
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
        if r.nosleepAvailable || r.state.nosleep != nil {
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

    private func refreshStatusRows() {
        guard menu.numberOfItems >= 2 else { return }
        let r = app.reconciler!
        menu.item(at: 0)?.attributedTitle = statusTitle(.caf)
        if r.nosleepAvailable || r.state.nosleep != nil { menu.item(at: 1)?.attributedTitle = statusTitle(.nosleep) }
        refresh()
    }

    private func statusTitle(_ mode: Mode) -> NSAttributedString {
        let session = app.reconciler.state[mode]
        let title = NSMutableAttributedString(string: "\(mode.title): \(Format.status(session, now: Date()))")
        if session?.isUnlimited == true {
            title.append(NSAttributedString(string: "  ●", attributes: [.foregroundColor: NSColor.systemOrange]))
        }
        return title
    }

    private func statusRow(_ mode: Mode) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = statusTitle(mode)
        item.isEnabled = true   // enabled with no action: drawn normally, not greyed
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
        let parent = NSMenuItem(title: mode == .caf ? "Caffeinate" : "Nosleep (lid closed)", action: nil, keyEquivalent: "")
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
