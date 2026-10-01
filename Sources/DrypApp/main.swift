import AppKit
import DrypCore

let paths = Paths.live
let log = FileLog(url: paths.logFile)

// Exactly one agent: the launchd-managed one. Opened from Finder or Spotlight, hand off and leave.
// DRYP_DEV=1 runs in place for development (`DRYP_DEV=1 swift run DrypApp`).
let environment = ProcessInfo.processInfo.environment
if environment["XPC_SERVICE_NAME"] != Paths.label && environment["DRYP_DEV"] != "1" {
    StartMarker.touch(paths)
    if !AgentControl.live(paths: paths).start() { log.write("handoff: couldn't start the launchd agent") }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(paths: paths, log: log)
app.delegate = delegate
app.run()
