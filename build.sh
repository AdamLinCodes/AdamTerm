#!/bin/sh
# Build AdamTerm.app into ./dist. Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -v '^\[' || true
APP=dist/AdamTerm.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/AdamTerm "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
[ "$1" = "--run" ] && open "$APP"
