# dryp

Keeps your Mac awake from the menu bar or the terminal, in two independent ways:

- **caf** — screen and everything stay on (what `caffeinate -dimsu` does).
- **nosleep** — sleep is disabled, so you can close the lid and your agents keep running
  (what `pmset -a disablesleep 1` does). It always cleans up after itself.

## Install

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/00mkp/dryp.git
cd dryp
./install.sh            # asks whether to enable nosleep
```

`--nosleep` / `--no-nosleep` skip the question. nosleep needs root, so it adds one file,
`/etc/sudoers.d/dryp`, allowing exactly `pmset -a disablesleep 0` and `1` without a password —
nothing else. Without it, dryp runs caf-only.

The installer builds from source (no Gatekeeper prompts, and you can read what you run), puts
`dryp.app` in `~/Applications` (override with `APP_DIR=…`) and the `dryp` command in `~/.local/bin`.

Notifications: on first launch macOS may not show a permission prompt. If no banners appear,
enable dryp in System Settings → Notifications. The app has to live in `~/Applications` (or
another normal folder) for notifications to work.

## Usage

```
dryp caf [N] [-h]        keep awake N minutes (hours with -h); no N = no limit
dryp caf off
dryp nosleep [N] [-h]    disable sleep (lid can close) N minutes / hours; no N = no limit
dryp nosleep off         also restores sleep that something else disabled
dryp off                 stop both
dryp status
dryp app start | stop    stop = end both modes, restore sleep, quit
dryp app login on | off  Open at Login
dryp update [PATH]       rebuild and reinstall; stops any active session, keeps prefs
dryp uninstall [--force]
```

`-h` means hours, so a bare `dryp caf -h` (no number) is a usage error; help is `--help` only.

`dryp update` stops any active caf/nosleep session (the agent restarts); your preferences and
the nosleep choice are kept. `dryp uninstall` refuses to remove anything while sleep that dryp
disabled can't be restored; `--force` goes ahead anyway, still tries a restore, and prints the
manual command if it needs one.

```
$ dryp caf 2 -h
caf on for 2h (until 18:40)
$ dryp status
caf:      on · 1h59m left (until 18:40)
nosleep:  off
pmset:    SleepDisabled 0
agent:    running (pid 4411)
```

## Menu bar

Two fixed glyphs: a cup (caf) and a laptop (nosleep) — dimmed when off, full when on, with an
orange dot when a mode has no time limit. The menu has presets (30 min to 8 hr), No Limit,
Custom…, Stop, Stop All, per-mode "Show Time in Menu Bar", and Open at Login.

You'll get a banner 5 minutes before a timed session ends (with **Extend 1 hr**), and when it
ends. nosleep stops by itself on battery at 10 %.

## Safety

nosleep changes a system setting that survives closing the terminal and rebooting, so dryp:

- restores sleep on every way it stops — Quit, `dryp app stop`, logout, shutdown, uninstall —
  and only exits once `SleepDisabled` reads 0;
- is restarted by launchd if it crashes, and checks at every login, so a power cut mid-session
  is cleaned up at the next boot;
- never undoes a `disablesleep` it didn't set without being asked, but flags it in the menu
  with a one-click **Restore Sleep**.

## How it works

The menu-bar agent is the only thing that touches power settings. The CLI and the menu write
requests to `~/.config/dryp/state.json`; the agent notices (a kernel file event — no polling),
acts, and records what it did in `~/.local/share/dryp/applied.json`, which the CLI waits for so it
can report the real result. Log: `~/Library/Logs/dryp.log`.

## Testing

`test/verify.sh` runs the real-machine checks against an installed dryp (about 4 minutes; it
asks for your password once to test the missing-sudoers case). Unit tests: `scripts/test.sh`.

## License

MIT
