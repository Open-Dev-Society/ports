#!/bin/sh
# Builds dist/Ports.app, a menu bar app with the `ports` command inside it.
# Runs on Apple silicon and Intel. The universal build needs Xcode, not just the Command Line Tools.
set -eu
cd "$(dirname "$0")"

version=$(sed -n 's/.*portsVersion = "\(.*\)"/\1/p' Sources/PortsCore/Ports.swift)
swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
app=dist/Ports.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/PortsApp" "$bin/PortsPanel" "$bin/ports" "$app/Contents/MacOS/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PortsApp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>io.github.open-dev-society.ports</string>
  <key>CFBundleName</key><string>Ports</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Open Dev Society. AGPL-3.0.</string>
</dict>
</plist>
PLIST
# ponytail: ad-hoc signature, so macOS warns on first open. Removing that needs a Developer ID and notarization.
codesign --force --sign - "$app/Contents/MacOS/ports"
codesign --force --sign - "$app/Contents/MacOS/PortsPanel"
codesign --force --sign - "$app"
echo "Built $app $version"
