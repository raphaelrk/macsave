#!/bin/bash
# Builds MacSave.app. Usage: ./build.sh [--install]  (--install copies to ~/Applications and launches it)
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/MacSave.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacSave "$APP/Contents/MacOS/MacSave"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.raphaelrk.macsave</string>
  <key>CFBundleName</key><string>MacSave</string>
  <key>CFBundleExecutable</key><string>MacSave</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>MacSave reads the windows and tabs of your browsers, terminals and Finder so it can save them to a note.</string>
</dict></plist>
PLIST
IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')
if [ -n "${IDENTITY:-}" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "No signing identity found; ad-hoc signing (permissions must be re-granted after each rebuild)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
if [ "${1:-}" = "--install" ]; then
  pkill -x MacSave || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/MacSave.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/MacSave.app
  echo "Installed ~/Applications/MacSave.app"
fi
