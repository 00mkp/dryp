#!/usr/bin/env bash
# Builds dryp.app (agent + icon) and installs it to $APP_DIR (default ~/Applications).
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/Applications}"
case "$APP_DIR" in /*) ;; *) APP_DIR="$PWD/$APP_DIR" ;; esac
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
LABEL="io.github.00mkp.dryp"

echo "==> Building dryp.app (release)"
swift build -c release --product DrypApp
swift build -c release --product dryp-icon
BIN_DIR="$(swift build -c release --show-bin-path)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/dryp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DrypApp" "$APP/Contents/MacOS/dryp"

# The icon is drawn in code (Sources/DrypIcon); no binary icon is checked in.
"$BIN_DIR/dryp-icon" "$STAGE/dryp.iconset"
iconutil -c icns "$STAGE/dryp.iconset" -o "$APP/Contents/Resources/dryp.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>dryp</string>
  <key>CFBundleExecutable</key><string>dryp</string>
  <key>CFBundleIconFile</key><string>dryp</string>
  <key>CFBundleIdentifier</key><string>${LABEL}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>dryp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally; it never leaves this machine, so no Developer ID is involved.
codesign --force --sign - --identifier "$LABEL" "$APP"
mkdir -p "$APP_DIR"
rm -rf "$APP_DIR/dryp.app"
mv "$APP" "$APP_DIR/dryp.app"
# Register with LaunchServices so Finder, Spotlight and System Settings pick up the name and icon now.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR/dryp.app" || true
echo "Installed $APP_DIR/dryp.app"
