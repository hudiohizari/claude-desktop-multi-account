#!/bin/bash
# Build the menu bar app.  ./build.sh            -> build/Claude Clones.app
#                          ./build.sh --install  -> also copy to ~/Applications and register
set -euo pipefail
cd "$(dirname "$0")"

app="build/Claude Clones.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -O -framework AppKit -o "$app/Contents/MacOS/ClaudeClones" ClaudeClones/*.swift

swiftc -O -framework AppKit -o build/makeicon tools/MakeIcon.swift
build/makeicon build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"

# LSUIElement: menu bar only, no Dock tile.
# The claude:// entry lets it be chosen as the handler; it does not claim the
# scheme on its own — that is a menu item you have to click.
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClaudeClones</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.local.claudeclones</string>
  <key>CFBundleName</key><string>Claude Clones</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Claude</string>
    <key>CFBundleURLSchemes</key><array><string>claude</string></array>
  </dict></array>
</dict></plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Claude Clones.app"
  cp -R "$app" "$HOME/Applications/"
  "$lsregister" -f "$HOME/Applications/Claude Clones.app"
  echo "Installed to ~/Applications/Claude Clones.app"
fi
