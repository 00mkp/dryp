# dryp — design

Date: 2026-09-30 · Target version: 0.1.0

## Goal

Replace the caffeinate/nosleep aliases and functions in `~/.zshrc` with one
macOS tool: a CLI (`dryp`) plus a native menu bar item, in the same family as
mutewake, punchclock and peel. It keeps the Mac awake in two independent ways:

- **caf** — what `caffeinate -dimsu` does today: screen and everything stay on.
  No root.
- **nosleep** — what `pmset -a disablesleep 1` does today: the lid can close
  and agents keep running. Needs root, via a narrow sudoers rule.

Both are time-bounded or unlimited, can run at the same time, and are
controlled identically from the terminal or the menu. The tool must never leave
`disablesleep` on without either watching it or flagging it.

### What it replaces

| Today (`~/.zshrc`) | dryp |
| --- | --- |
| `halfcaf`, `halfhalfcaf`, `onecaf` … `eightcaf` | `dryp caf 30`, `dryp caf 45`, `dryp caf 1 -h` … `dryp caf 8 -h` |
| `mincaf N` / `hourcaf N` | `dryp caf N` / `dryp caf N -h` |
| bare `caffeinate -dimsu` | `dryp caf` |
| `nosleep N` | `dryp nosleep N` |
| `nosleep-on` / `nosleep-off` | `dryp nosleep` / `dryp nosleep off` |
| shell-startup "sleep is DISABLED" warning | the agent's login check, which fixes or flags it |

## Decisions

- **One app, two independent modes.** They share all plumbing (agent, state,
  timers, notifications, menu item, install) but have separate commands,
  drivers, state entries and timers. Stopping one never touches the other.
- **Root via a narrow sudoers rule**, not a signed privileged helper. It keeps
  the build-from-source, no-Developer-ID model of the sibling projects and lets
  the agent restore sleep unattended. nosleep is optional at install; without
  it dryp runs caf-only.
- **One agent owns all effects (mutewake pattern).** The menu bar app runs as a
  launchd agent and is the only thing that creates power assertions or runs
  `pmset`. The CLI and the menu only write requests to a state file.
- **Deadlines are wall-clock times on disk**, so crashes and reboots resume or
  clean up correctly.
- **caf uses `IOPMAssertion` directly** rather than spawning `caffeinate`;
  assertions die with the process, so an orphaned hold is impossible.
- **Native `NSMenu`**, not a popover: nothing needs to stay open while clicking
  elsewhere.
- **SwiftPM package** (like peel), so the CLI can use swift-argument-parser and
  the core logic gets unit tests.
- **Installed to `~/Applications`** (overridable with `APP_DIR`, like peel) so
  Spotlight and Launchpad can find it.

## CLI

```
dryp caf [N] [-h|--hours]       keep awake N minutes (hours with -h); no N = no limit
dryp caf off
dryp nosleep [N] [-h|--hours]   disable sleep (lid can close) N minutes / hours; no N = no limit
dryp nosleep off
dryp off                        stop both
dryp status                     both modes, time left, real pmset readback, agent state
dryp app start | stop           launch / quit the agent (stop = full cleanup, see Lifecycle)
dryp app login on | off         Open at Login
dryp update [PATH]              pull, rebuild, reinstall (or from a dir / .tar.gz / .tgz / .zip)
dryp uninstall
dryp --help                     long form only: -h means hours
```

- **Numbers.** Minutes must be whole and ≥ 1. Hours (`-h`) accept decimals
  (`1.5`) and must produce ≥ 1 minute. The maximum is 8760 hours (one year). Anything else is a usage error, exit 2.
- **Replace semantics.** Starting a mode that is already running replaces that
  mode's deadline (and its no-limit flag). The other mode is untouched.
- **Honest results.** The CLI writes the request, then waits up to 2 s for the
  agent to acknowledge it (see State → `rev`). For nosleep it also reads
  `pmset -g live` itself. Only then does it print, e.g.
  `nosleep on for 90m (until 17:40)` or `caf on, no limit`.
  - Agent not running → `launchctl kickstart` (or bootstrap if unloaded) and
    retry once; still nothing → error, exit 1.
  - The agent rejected the request (nosleep not set up, low battery, `pmset`
    failed) → the reason, exit 1.
- **`status`** example:
  ```
  caf:      on · 42m left (until 16:52)
  nosleep:  on · no limit
  pmset:    SleepDisabled 1
  agent:    running (pid 4411)
  ```
  A mismatch (e.g. SleepDisabled 1 while dryp's nosleep is off) adds a warning
  line naming the fix (`dryp nosleep off`, or the menu's Restore Sleep).
  If nosleep isn't set up, its line reads `not set up — run ./install.sh --nosleep`.
- **Starting the agent.** Commands that change state (`caf`, `nosleep`, `off`,
  `app start`, `app login`) start the agent if needed. `status` never does; it
  reports `agent: not running`.
- **Exit codes:** 0 success, 1 failure, 2 usage.

## State

Two files with separate owners, so the agent can tell what it did from what
was requested.

**Requests — `~/.config/dryp/state.json`**, written by the CLI and the menu,
read by the agent:

```json
{ "version": 1,
  "rev": 17,
  "caf":     { "started": "2026-09-30T16:10:00Z", "until": "2026-09-30T16:52:00Z" },
  "nosleep": null,
  "restoreSleep": false,
  "prefs":   { "showTimeCaf": false, "showTimeNosleep": false, "openAtLogin": true } }
```

- A mode that is `null` is off; `until: null` means no limit.
- `restoreSleep` is a one-shot request (set by `dryp nosleep off`, `dryp off`,
  and the menu's Restore Sleep / Retry): the agent sets `disablesleep 0` even
  if dryp didn't set it, retries a failed restore immediately, then clears the
  flag. This is the only way a foreign `disablesleep 1` is undone — always by
  explicit request.
- `rev` is a monotonic revision: `max(previous + 1, current Unix time in ms)`,
  so it keeps rising even if `state.json` is deleted and recreated.
- Every write is a read-modify-write under an exclusive `flock` on
  `~/.config/dryp/state.lock`, written to a temp file and renamed into place.
  Every write increments `rev`.
- A file that fails to parse is renamed to `state.json.bad`, logged, and
  treated as "nothing requested" (which restores sleep if the agent had set it).

**Applied record — `~/.local/share/dryp/applied.json`**, written only by the
agent after it acts:

```json
{ "rev": 17, "cafHeld": true, "nosleepSet": false,
  "rejected": null, "restoreFailed": false }
```

- `rev` is the last request revision the agent has fully processed. The CLI's
  acknowledgement wait is "`applied.rev` ≥ the `rev` I wrote".
- `rejected` carries the reason if the agent refused the latest request; the
  agent also rolls the rejected mode back to `null` in `state.json`.
- `nosleepSet` is what makes a `disablesleep 1` **owned** (dryp set it) rather
  than **foreign**.

## Agent

An accessory `NSApplication` (`LSUIElement`) inside `dryp.app`, run by launchd.
Every input — a state file change, a timer, a battery change, waking, a clock
change, a menu action — goes through one reconcile step:

1. Read `state.json`, `applied.json`, the clock, the power source and battery
   level, and the live `SleepDisabled` value.
2. Ask the core **policy** what should be active: expire passed deadlines, stop
   nosleep on low battery, reject what can't be applied.
3. Make the drivers match. Write back any state changes (expired or rejected
   modes become `null`).
4. Read the real state back, write `applied.json`, refresh the icon and menu,
   send any notifications, and re-arm the single timer for the next event
   (a deadline, or a 5-minute warning).

Components:

- **Caf driver.** Holds the assertions that match `-dimsu`:
  `PreventUserIdleDisplaySleep` (-d), `PreventUserIdleSystemSleep` (-i),
  `PreventDiskIdle` (-m) and `PreventSystemSleep` (-s, effective on AC only),
  plus `IOPMAssertionDeclareUserActivity` once at start (-u).
- **Nosleep driver.** Runs `sudo -n /usr/bin/pmset -a disablesleep 1|0`, then
  reads `pmset -g live` back; the readback is the result, not the exit code.
  It never prompts for a password. It detects setup with
  `sudo -n -l /usr/bin/pmset -a disablesleep 0`.
  It sets only `disablesleep`; display sleep is unaffected (as today).
- **Watchers.** State directory via a `DispatchSource` vnode source that
  re-arms if the file is replaced (as in mutewake); power source via
  `IOPSNotificationCreateRunLoopSource`; wake via `NSWorkspace.didWakeNotification`;
  clock changes via `NSSystemClockDidChange`. No polling.
- **Notifier.** `UNUserNotificationCenter`, with an `Extend 1 hr` action on
  warnings.
- **Status menu.** See Menu.

### Single instance

The launchd-managed process is the only agent. When `dryp.app` is opened any
other way (Finder, Spotlight), it detects that it was not started by launchd
(`XPC_SERVICE_NAME` ≠ the label), kickstarts the launchd job, and exits.

## Menu

### Icon

Two **fixed slots**, always present: a cup for caf and a laptop for nosleep.
They are template images (light/dark automatic), except the orange dot.

| Slot state | Drawing |
| --- | --- |
| idle | dimmed glyph (`cup.and.saucer`, `laptopcomputer`) |
| on, timed | full-strength glyph (`cup.and.saucer.fill`; `laptopcomputer` has no fill variant, so it goes from dimmed to full) |
| on, no limit | full-strength glyph + small orange dot |
| nosleep: foreign `disablesleep 1`, or restore failed | laptop slot orange-dotted / tinted, regardless of dryp's own state |
| nosleep not set up | laptop slot hidden; caf slot only |

**Show time** is per slot and off by default. With it on, the slot shows its
time remaining at minute precision (`42m`, `3h12m`) or `∞` for no limit (the
dot stays). Neither, one, or both can be on.

### App icon

`dryp.app` has a real icon, so Finder, Spotlight, System Settings (Login Items,
Notifications) and the About panel show it even though there is no Dock icon.
Like peel, it is drawn in code and turned into an `.icns` at build time — no
binary is checked in: the white `cup.and.saucer.fill` glyph on a warm
coffee-brown gradient tile, on the macOS icon grid (an 824/1024 rounded square,
centred, with a soft shadow). A small `dryp-icon` executable writes the
`.iconset`; `build-app.sh` runs `iconutil` and sets `CFBundleIconFile`.

### Dropdown

```
Caffeinate: on · 42m left (until 16:52)
Nosleep: on · no limit  ●
────────────────────────
Caffeinate            ▸  30 min · 45 min · 1 hr · 2 hr · 4 hr · 8 hr
                         No Limit
                         Custom…
                         ─────
                         Stop
Nosleep               ▸  (same)
────────────────────────
Stop All                              ⌘.
────────────────────────
Show Time in Menu Bar ▸  ✓ Caffeinate
                           Nosleep
✓ Open at Login
About dryp
Quit                                  ⌘Q
```

- Status rows refresh every few seconds while the menu is open (a timer in the
  event-tracking run loop mode).
- **Custom…** opens a small dialog: a number field plus a Minutes/Hours picker,
  validated with the same rules as the CLI.
- Foreign `disablesleep 1` adds a row `Sleep disabled outside dryp` and an item
  **Restore Sleep**, which runs `disablesleep 0` and reads it back.
- nosleep not set up: the Nosleep submenu is replaced by a disabled
  `Nosleep: not set up` row and **Set Up…**, which explains
  `./install.sh --nosleep`.
- Restore failure: a row `Couldn't restore sleep` with **Retry**, and the
  exact manual command.
- Every menu action writes `state.json` like the CLI does; the menu never
  drives a driver directly.

## Notifications and safety

- **Warning.** 5 minutes before a timed session ends: "Nosleep ends in 5 min"
  / "Caffeinate ends in 5 min", with **Extend 1 hr**, which adds an hour to that
  mode's current deadline. Not sent for no-limit sessions or sessions shorter
  than 10 minutes.
- **End notice.** "Nosleep ended — sleep restored" / "Caffeinate ended". Not
  sent when the user stopped the mode themselves.
- **Low battery.** On battery at ≤ 10 %, nosleep stops (timed or no limit) with
  "Nosleep stopped: battery at 9 %". It does not restart on charge. Starting
  nosleep on battery at ≤ 10 % is rejected. caf is unaffected.
- **Deadline passed while asleep** (e.g. lid closed during caf): the session
  ends at wake, with the normal end notice.
- **Crash.** launchd restarts the agent; it reconciles from the two files.
  caf assertions are re-created; nosleep is kept or ended by its deadline.
- **Reboot / login.** Unexpired sessions resume; expired ones are cleaned up
  with "Nosleep ended while your Mac was off". An owned `disablesleep 1` with
  no live nosleep request is restored.
- **Foreign `disablesleep 1`** (not set by dryp): never undone automatically.
  The laptop slot gets the orange dot, the menu offers Restore Sleep, and one
  notification is sent per occurrence.
- **Root failures.** Rule missing or `sudo -n` refused → the nosleep request is
  rejected and rolled back, with the setup hint. **Restore** (`disablesleep 0`)
  failing → retry with backoff (5 s, 30 s, 2 min, then every 5 min), the laptop
  slot turns orange, a notification gives the exact manual command, and
  `restoreFailed` is recorded for `status` and the next login check.

## Lifecycle

| Action | Effect |
| --- | --- |
| Stop All | Both modes end, sleep restored, agent stays in the menu bar |
| Quit (menu, ⌘Q, `dryp app stop`) | Shutdown routine, then exit. Stays gone until the next login (if Open at Login is on) or the next `dryp` command |
| Open at Login off + Quit | Effectively off: nothing runs except the brief login check |
| `dryp uninstall` | Everything removed |

**Shutdown routine.** Used by Quit, `app stop`, `uninstall`, logout, shutdown
and restart, and `launchctl` stopping the agent (SIGTERM). It clears both
modes in `state.json` first, so nothing resumes them, then:

1. Release the caf assertions.
2. If `nosleepSet`, run `disablesleep 0`.
3. Read `SleepDisabled` back; exit only when it is 0.
4. If the restore fails and the agent is interactive (Quit from the menu), show
   an alert with the manual command and **Retry** / **Quit Anyway**. When the
   exit is forced (SIGTERM, logout), log it and leave `restoreFailed` set for
   the next login check.

Quit asks for confirmation first if a mode is active. Exits are status 0, and
the plist's `KeepAlive: { SuccessfulExit: false }` keeps a deliberate exit
from respawning, while a crash is restarted.

**Login check.** launchd starts the agent at every login (`RunAtLoad`). It
reconciles as above. Then, if `openAtLogin` is false, no mode is active, and
nothing is flagged (no foreign or failed `disablesleep`), it exits 0 without
showing the icon. Otherwise it stays. A live session always keeps it running,
whatever the setting.

## Install, update, uninstall

**`install.sh`**

- Checks macOS ≥ 13 and the Swift toolchain, then `swift build -c release`.
- Assembles `dryp.app` (bundle ID `io.github.00mkp.dryp`, `LSUIElement`) in
  `$APP_DIR` (default `~/Applications`) and ad-hoc signs it. Installs the CLI
  to `~/.local/bin/dryp`.
- Generates `~/Library/LaunchAgents/io.github.00mkp.dryp.plist`
  (`RunAtLoad`, `KeepAlive: { SuccessfulExit: false }`,
  `ProcessType: Interactive`), lints it with `plutil`, and bootstraps it.
- Writes `~/.local/share/dryp/manifest` (version, source path, app path,
  nosleep enabled, install time), which `update` relies on.
- **nosleep setup**, by prompt or `--nosleep` / `--no-nosleep`:
  > Enable nosleep (lid-closed mode)? This adds /etc/sudoers.d/dryp, allowing
  > only `pmset -a disablesleep 0` and `1` without a password. [Y/n]

  It renders
  `<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1`
  (user from `id -un`) to a temp file, checks it with `visudo -cf`, and only
  then runs `sudo install -m 0440 -o root -g wheel` into `/etc/sudoers.d/dryp`.
  A failed check aborts that step and leaves sudoers untouched.
- Does not edit `~/.zshrc`. It prints a suggested alias block and notes that
  the old `nosleep` function and the startup warning should be removed, since
  they would shadow `dryp`'s behaviour:
  ```sh
  alias halfcaf='dryp caf 30'   halfhalfcaf='dryp caf 45'   onecaf='dryp caf 60'
  alias twocaf='dryp caf 2 -h'  fourcaf='dryp caf 4 -h'     eightcaf='dryp caf 8 -h'
  mincaf()  { dryp caf "$1"; }
  hourcaf() { dryp caf "$1" -h; }
  nosleep() { dryp nosleep "$@"; }
  alias nosleep-on='dryp nosleep'  nosleep-off='dryp nosleep off'
  ```
- Prints a PATH note if `~/.local/bin` is missing, as mutewake does.

**`dryp update [PATH]`** — `git pull` in the recorded source (or uses PATH),
rebuilds and reinstalls. It keeps state, prefs and the nosleep choice.

**`dryp uninstall`** — runs the shutdown routine, boots out and removes the
launchd agent, then removes the app, CLI, `~/.config/dryp`,
`~/.local/share/dryp` and the log, and `/etc/sudoers.d/dryp` (asks for the
password once).

**Logging** — one line per event to `~/Library/Logs/dryp.log`, e.g.
`nosleep on until 17:40 (cli)`, `low battery: nosleep stopped`,
`restore failed, retrying in 30s`. Debugging only; there is no activity menu.

## Package layout

```
Package.swift            swift-tools 6.0, macOS 13, swift-argument-parser
Sources/
  DrypCore/              pure logic; no AppKit, no side effects
                         · Duration parsing and validation
                         · State and Applied models, the locked atomic store
                         · Policy: (state, applied, now, power, sleepDisabled) → desired effects
                         · Reconciler, written against driver protocols:
                           PowerAssertions, SleepSetting, PowerSource, Clock, Notifier
                         · Next-event scheduling (deadlines, warnings)
  DrypCLI/               ArgumentParser commands (help names: --help only)
  dryp/                  CLI executable
  DrypIcon/              AppKit drawing of the app icon (tested for size and ink)
  dryp-icon/             writes the .iconset for build-app.sh
  DrypApp/               AppKit agent: real drivers, watchers, status menu, single-instance handoff
Tests/
  DrypCoreTests/         parsing, policy, scheduling, store, reconciler against fakes
  DrypCLITests/          argument parsing, output and exit codes
test/verify.sh           end-to-end checks on a real machine
install.sh · VERSION · README.md · LICENSE
```

## Testing

- **Unit (`swift test`).** Duration parsing (minutes, `-h`, decimals,
  rejects); deadline and warning math, including sessions under 10 min;
  policy for every combination of modes × battery × power source; owned vs
  foreign `disablesleep`; store round trip, `rev`, locking and corrupt files.
- **Reconciler against fakes.** Crash-and-resume, reboot with expired and
  unexpired sessions, low battery mid-session, rejected requests rolling back,
  restore failure and backoff, and the shutdown routine's ordering — all
  without root or hardware.
- **`test/verify.sh` (real machine).** `dryp caf 1` → dryp's assertions
  appear in `pmset -g assertions` and disappear after a minute; `dryp nosleep 1`
  → SleepDisabled 1, then 0 after a minute; `kill -9` the agent during nosleep
  → it is restarted and still restores on time; `dryp app stop` during nosleep
  → SleepDisabled 0 before exit; nosleep with the sudoers rule absent → clean
  rejection, exit 1.
- **Spike first.** Before building on it, confirm that an ad-hoc-signed bundle
  can request notification permission and receive an action (`Extend 1 hr`)
  through `UNUserNotificationCenter`. If it can't, warnings become plain
  banners and Extend lives only in the menu.

## Out of scope

- Signed or notarized prebuilt releases, Homebrew.
- "Stay awake until process X exits".
- A configurable battery threshold or warning lead time.
- An activity history in the menu.
- Moving mutewake into `~/Applications` (a separate change in that repo).
