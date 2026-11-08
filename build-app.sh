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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/PortsApp" "$bin/PortsPanel" "$bin/PortsUpdater" "$bin/ports" "$app/Contents/MacOS/"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
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
  <key>SUFeedURL</key><string>https://github.com/Open-Dev-Society/ports/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>JtslS4nnoVfZjF74OL29HRJOHsqNnK8pbH7+QsiLXAY=</string>
  <key>SUEnableAutomaticChecks</key><false/>
</dict>
</plist>
PLIST
# ponytail: ad-hoc signature, so macOS warns on first open. Removing that needs a Developer ID and notarization.
# Inside out: Sparkle's helpers, the framework, then each program and the app.
fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$fw/XPCServices/Installer.xpc" "$fw/XPCServices/Downloader.xpc" "$fw/Autoupdate" "$fw/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign - "$part"
done
codesign --force --sign - "$app/Contents/MacOS/PortsUpdater"
codesign --force --sign - "$app/Contents/MacOS/ports"
codesign --force --sign - "$app/Contents/MacOS/PortsPanel"
codesign --force --sign - "$app"
echo "Built $app $version"
