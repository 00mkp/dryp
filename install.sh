#!/usr/bin/env bash
# dryp installer.
#
# Builds from source, installs the `dryp` CLI and dryp.app, generates the launchd agent for THIS machine,
# and optionally installs the sudoers rule nosleep needs. The agent plist can't be a static file: launchd
# doesn't expand "~", so absolute paths are written at install time.
#
#   ./install.sh                 asks whether to enable nosleep
#   ./install.sh --nosleep       enable nosleep (installs /etc/sudoers.d/dryp)
#   ./install.sh --no-nosleep    caf only (removes /etc/sudoers.d/dryp if present)
#
# Environment: APP_DIR (default ~/Applications); DRYP_SOURCE overrides the source path recorded for
# `dryp update` (used when updating from an archive, whose unpacked folder is temporary).
set -euo pipefail

LABEL="io.github.00mkp.dryp"
APP_DIR="${APP_DIR:-$HOME/Applications}"
case "$APP_DIR" in /*) ;; *) APP_DIR="$(pwd)/$APP_DIR" ;; esac
export APP_DIR
BINDIR="$HOME/.local/bin"
DATADIR="$HOME/.local/share/dryp"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SUDOERS="/etc/sudoers.d/dryp"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

NOSLEEP=ask
for arg in "$@"; do
  case "$arg" in
    --nosleep) NOSLEEP=yes ;;
    --no-nosleep) NOSLEEP=no ;;
    --help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown option: $arg (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "dryp is macOS-only."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 13 )) || die "dryp needs macOS 13 or later (this is $(sw_vers -productVersion))."
command -v swift >/dev/null 2>&1 || die "swift not found. Install the Xcode Command Line Tools: xcode-select --install"
[[ -f "$SRC/VERSION" ]] || die "$SRC/VERSION is missing; this is not a complete source tree."
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
cd "$SRC"

echo "==> Building dryp $VERSION"
swift build -c release --product dryp

# --- nosleep: the sudoers rule -------------------------------------------------------------------
# Runs before anything is stopped or replaced, and no failure here is fatal: a failed nosleep step
# downgrades to caf-only with a warning instead of leaving a half-done install.
TMP_RULE=""
trap '[[ -z "$TMP_RULE" ]] || rm -f "$TMP_RULE"' EXIT

rule_works() {
  # Re-applies the CURRENT SleepDisabled value: a no-op change that succeeds without a password only if
  # a NOPASSWD rule covers exactly `pmset -a disablesleep <current>`. -k ignores cached credentials.
  local current
  current="$(pmset -g live | awk '/SleepDisabled/{print $2}')"
  sudo -k -n /usr/bin/pmset -a disablesleep "${current:-0}" >/dev/null 2>&1
}

install_rule() {
  TMP_RULE="$(mktemp)" || return 1
  printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$(id -un)" > "$TMP_RULE"
  sudo /usr/bin/install -m 0440 -o root -g wheel "$TMP_RULE" "$SUDOERS.tmp" || return 1
  # sudo ignores files with a dot in the name, so the staged .tmp file is inert until the final mv.
  if ! sudo /usr/sbin/visudo -c -f "$SUDOERS.tmp" >/dev/null; then
    sudo /bin/rm -f "$SUDOERS.tmp"
    echo "warning: the generated sudoers rule failed visudo -c; sudoers was left untouched" >&2
    return 1
  fi
  sudo /bin/mv "$SUDOERS.tmp" "$SUDOERS" || { sudo /bin/rm -f "$SUDOERS.tmp"; return 1; }
  rule_works || { echo "warning: installed $SUDOERS, but sudo still asks for a password for pmset" >&2; return 1; }
}

if [[ "$NOSLEEP" == ask ]]; then
  if [[ -t 0 ]]; then
    echo
    echo "Enable nosleep (lid-closed mode)? This adds $SUDOERS, allowing only"
    printf '`pmset -a disablesleep 0` and `1` without a password. [Y/n] '
    read -r reply || reply=""
    case "$reply" in [nN]*) NOSLEEP=no ;; *) NOSLEEP=yes ;; esac
  else
    echo "note: not a terminal, so nosleep is left off (rerun with --nosleep to enable it)"
    NOSLEEP=no
  fi
fi

if [[ "$NOSLEEP" == yes ]]; then
  if rule_works; then
    echo "==> nosleep: sudoers rule already in place"
  else
    echo "==> nosleep: installing $SUDOERS (sudo will ask for your password)"
    if ! install_rule; then
      echo "warning: nosleep could not be enabled; continuing with caf only (rerun with --nosleep to retry)" >&2
      NOSLEEP=no
    fi
  fi
else
  if [[ -f "$SUDOERS" ]]; then
    echo "==> nosleep: removing $SUDOERS"
    sudo /bin/rm -f "$SUDOERS" || echo "warning: could not remove $SUDOERS; remove it manually with: sudo rm $SUDOERS" >&2
  fi
fi

echo "==> Stopping any running agent (active sessions end and sleep is restored)"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
pkill -f "$APP_DIR/dryp.app/Contents/MacOS/dryp" 2>/dev/null || true

echo "==> Installing the dryp command"
mkdir -p "$BINDIR" "$DATADIR"
install -m 755 "$(swift build -c release --show-bin-path)/dryp" "$BINDIR/dryp"

scripts/build-app.sh

# --- launchd agent -------------------------------------------------------------------------------
echo "==> Generating the launchd agent"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_DIR/dryp.app/Contents/MacOS/dryp</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/dryp.err.log</string>
</dict>
</plist>
PLIST_EOF
plutil -lint "$PLIST" >/dev/null || die "generated plist is malformed"

echo "==> Recording the install manifest"
cat > "$DATADIR/manifest" <<MANIFEST_EOF
version=$VERSION
source=${DRYP_SOURCE:-$SRC}
app_dir=$APP_DIR
nosleep=$NOSLEEP
installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MANIFEST_EOF

echo "==> Starting"
touch "$DATADIR/start"     # stay in the menu bar this launch even if Open at Login is off
launchctl bootstrap "$DOMAIN" "$PLIST" || true
sleep 1
[[ "$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null)" == *"pid = "* ]] || die "the agent didn't start. See ~/Library/Logs/dryp.err.log"

cat <<'DONE'

dryp is installed and running.

To replace your old aliases, put this in ~/.zshrc (and delete the old nosleep function and the
"sleep is DISABLED" startup check — they would shadow dryp):

  alias halfcaf='dryp caf 30' halfhalfcaf='dryp caf 45' onecaf='dryp caf 60'
  alias twocaf='dryp caf 2 -h' fourcaf='dryp caf 4 -h' eightcaf='dryp caf 8 -h'
  mincaf()  { dryp caf "$1"; }
  hourcaf() { dryp caf "$1" -h; }
  nosleep() { dryp nosleep "$@"; }
  alias nosleep-on='dryp nosleep' nosleep-off='dryp nosleep off'

Try:  dryp status
DONE

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo
     echo "NOTE: $BINDIR is not on your PATH. Add this to ~/.zshrc:"
     echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
