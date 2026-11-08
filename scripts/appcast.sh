#!/bin/sh
# Signs the release zip for Sparkle and writes dist/appcast.xml, the feed installed copies check once a day.
# Needs SPARKLE_ED_PRIVATE_KEY (the release workflow's secret) and notes.md (the release notes).
# Usage: scripts/appcast.sh VERSION
set -eu
cd "$(dirname "$0")/.."
version=$1
zip="dist/Ports-$version.zip"
test -n "${SPARKLE_ED_PRIVATE_KEY:-}" || { echo "SPARKLE_ED_PRIVATE_KEY is not set" >&2; exit 1; }

tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz | tar -xJ -C "$tools"
(umask 077; printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$tools/key")
signature=$("$tools/bin/sign_update" --ed-key-file "$tools/key" "$zip")

# The release notes as plain HTML for Sparkle's window: headings and bullet points are all they use.
notes=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/\*\*//g' -e 's/`//g' notes.md | awk '
  /^##+ / { if (list) { print "</ul>"; list = 0 } sub(/^#+ /, ""); print "<h3>" $0 "</h3>"; next }
  /^- /   { if (!list) { print "<ul>"; list = 1 } print "<li>" substr($0, 3) "</li>"; next }
  /^$/    { next }
  /^>|^\[/ { next }
  { if (list) { print "</ul>"; list = 0 } print "<p>" $0 "</p>" }
  END { if (list) print "</ul>" }')

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ports</title>
    <item>
      <title>Ports $version</title>
      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$notes]]></description>
      <enclosure url="https://github.com/Open-Dev-Society/ports/releases/download/v$version/Ports-$version.zip" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
XML
echo "Wrote dist/appcast.xml for $version"
