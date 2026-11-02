#!/bin/sh
# Builds the release files in dist/: a disk image, a zip and their checksums.
set -eu
cd "$(dirname "$0")/.."

./build-app.sh
version=$(sed -n 's/.*portsVersion = "\(.*\)"/\1/p' Sources/PortsCore/Ports.swift)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

ditto dist/Ports.app "$stage/Ports.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname Ports -srcfolder "$stage" -ov -format UDZO "dist/Ports-$version.dmg"
ditto -c -k --keepParent dist/Ports.app "dist/Ports-$version.zip"
(cd dist && shasum -a 256 "Ports-$version.dmg" "Ports-$version.zip" > "Ports-$version.sha256")
ls -lh dist/Ports-"$version".*
