#!/usr/bin/env bash
# Runs the test suite (extra arguments go to `swift test`, e.g. --filter PolicyTests).
# On Macs with only the Command Line Tools (no Xcode), SwiftPM must be told where Swift Testing
# lives, or it builds the tests and then silently runs none of them.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ ! -d /Applications/Xcode.app ] && [ -d "$CLT/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
    "$@"
fi
exec swift test "$@"
