# Notification spike (2026-09-30)

Outcome: ACTIONS_OK

An ad-hoc-signed LSUIElement bundle got notification permission, posted a banner with an
"Extend 1 hr" action, and received the action callback when it was clicked
(`authorized: true`, `added: ok`, `ACTION: extend`).

What it took:
- **Launch through LaunchServices** (`open`), not by executing the binary from a shell.
- **The bundle must live in a normal location** (`~/Applications`). Copies run from `/private/tmp` were
  refused immediately ("Notifications are not allowed for this application") with no prompt.
- **The deployment target must not exceed the running OS.** Plain `swiftc` here targets macOS 28.0 on
  macOS 27, and LaunchServices refuses to open the app (-10825). SwiftPM's `.macOS(.v13)` avoids this.
- **The first prompt didn't appear reliably.** The human enabled the app in System Settings →
  Notifications, after which authorization succeeded. dryp asks once at launch and logs the result, so a
  missing prompt shows up in `~/Library/Logs/dryp.log`.

mutewake's log shows the same refusal ("not allowed"), falling back to osascript, so mutewake's
fallback path is live on this Mac.

Consequence for Task 14: use UserNotifier with the Extend category, with permission handling matched
to peel and mutewake: ask if undetermined, alerts only, respect a denial, and fall back to osascript only
on errors.
