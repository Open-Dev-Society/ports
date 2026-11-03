#!/bin/sh
# Builds the release files in dist/: a disk image, a zip and their checksums.
set -eu
cd "$(dirname "$0")/.."

./build-app.sh
version=$(sed -n 's/.*portsVersion = "\(.*\)"/\1/p' Sources/PortsCore/Ports.swift)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# dmgbuild lays out the window (background, icon positions) without scripting Finder, so it works on CI.
python3 -m venv "$stage/venv"
"$stage/venv/bin/pip" install --quiet dmgbuild==1.6.7
"$stage/venv/bin/dmgbuild" -s scripts/dmg-settings.py -D app=dist/Ports.app Ports "dist/Ports-$version.dmg"
ditto -c -k --keepParent dist/Ports.app "dist/Ports-$version.zip"
(cd dist && shasum -a 256 "Ports-$version.dmg" "Ports-$version.zip" > "Ports-$version.sha256")
ls -lh dist/Ports-"$version".*
