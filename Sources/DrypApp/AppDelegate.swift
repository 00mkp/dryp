import AppKit
import DrypCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let paths: Paths
    let log: FileLog
    private(set) var reconciler: Reconciler!
    private var menu: StatusMenu?
    private var watcher: DirectoryWatcher?
    private var power: IOPowerSource!
    private var notifier: UserNotifier!
    private var timer: Timer?
    private var sigterm: DispatchSourceSignal?
    private var shuttingDown = false

    init(paths: Paths, log: FileLog) {
        self.paths = paths
        self.log = log
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let startRequested = StartMarker.consume(paths)
        power = IOPowerSource()
        notifier = UserNotifier(log: log.write)
        reconciler = Reconciler(
            store: StateStore(paths: paths), appliedStore: AppliedStore(paths: paths),
            caf: IOPMCafAssertions(), sleep: SudoPmset(log: log.write), power: power, notifier: notifier,
            now: Date.init, bootTime: BootTime.current(), log: log.write)
        log.write("agent started (dryp \(DrypVersion.current))")

        installSigterm()
        let next = reconciler.reconcile()
        if LoginCheck.shouldExit(state: reconciler.state, applied: reconciler.applied,
                                 foreign: reconciler.foreign, startRequested: startRequested) {
            log.write("login check: nothing to watch and Open at Login is off; exiting")
            // Notification posts are async; give an end notice from that first reconcile time to be delivered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
            return
        }

        notifier.onExtend = { [weak self] mode in
            self?.reconciler.extend(mode, by: 3600)
            self?.reconcile()
        }
        notifier.requestAuthorization()
        menu = StatusMenu(app: self)
        watcher = DirectoryWatcher(dir: paths.configDir, log: log.write) { [weak self] in self?.reconcile() }
        power.onChange = { [weak self] in self?.reconcile() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
        arm(next)
        menu?.refresh()
    }

    // MARK: - Reconcile loop

    func reconcile() {
        guard !shuttingDown, let reconciler else { return }
        arm(reconciler.reconcile())
        menu?.refresh()
    }

    /// One timer, for the next warning, deadline or restore retry. A quarter second late so `until <= now`.
    private func arm(_ date: Date?) {
        timer?.invalidate()
        timer = nil
        guard let date else { return }
        let t = Timer(fire: max(date, Date()).addingTimeInterval(0.25), interval: 0, repeats: false) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Actions (the menu calls these; each writes state.json exactly like the CLI)

    func request(_ mode: Mode, seconds: TimeInterval?) {
        let now = Date().wholeSeconds
        let written: DrypState
        do {
            written = try StateStore(paths: paths).update {
                $0[mode] = Session(started: now, until: seconds.map { now.addingTimeInterval($0) })
            }
        } catch {
            Alerts.info("Couldn't start \(mode.title)", "\(error)")
            return
        }
        reconcile()
        if let r = reconciler.applied.rejected, r.mode == mode, r.rev >= written.rev {
            Alerts.info("Couldn't start \(mode.title)", r.reason)
        }
    }

    func stop(_ modes: [Mode]) {
        _ = try? StateStore(paths: paths).update { s in
            for m in modes { s[m] = nil }
            if modes.contains(.nosleep) { s.restoreSleep = true }
        }
        reconcile()
    }

    /// Menu "Restore Sleep" and "Retry".
    func restoreSleep() {
        _ = try? StateStore(paths: paths).update { $0.restoreSleep = true }
        reconcile()
    }

    func setPref(_ body: (inout Prefs) -> Void) {
        _ = try? StateStore(paths: paths).update { body(&$0.prefs) }
        reconcile()
    }

    func quitFromMenu() {
        if reconciler.state.anyActive && !Alerts.confirmQuit() { return }
        shutdownAndExit(interactive: true)
    }

    // MARK: - Shutdown

    private func installSigterm() {
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { [weak self] in self?.shutdownAndExit(interactive: false) }
        src.resume()
        sigterm = src
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Logout and restart arrive here.
        if !shuttingDown { shutdownAndExit(interactive: false) }
        return .terminateNow
    }

    /// Clears both modes, releases caf, restores sleep, and exits only once SleepDisabled reads 0 — or, when
    /// interactive, when the user picks Quit Anyway. Exit status 0 so launchd doesn't respawn a deliberate quit.
    private func shutdownAndExit(interactive: Bool) {
        if shuttingDown {
            log.write("shutdown: already in progress; exiting")
            exit(0)
        }
        shuttingDown = true
        timer?.invalidate()
        while !reconciler.shutdown() {
            guard interactive else {
                log.write("shutdown: sleep could not be restored; flagged for the next login check")
                break
            }
            if Alerts.restoreFailed() == .quitAnyway {
                log.write("shutdown: user chose Quit Anyway with sleep still disabled")
                break
            }
        }
        log.write("agent exiting")
        exit(0)
    }
}
