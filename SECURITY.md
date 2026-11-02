# Security policy

Ports inspects and stops processes on your Mac, and it briefly holds their environment variables in memory for Undo, so we take security reports seriously.

## Reporting a vulnerability

Please don't open a public issue. Use [GitHub's private reporting](https://github.com/Open-Dev-Society/ports/security/advisories/new), or email opendevsociety@gmail.com.

Include what you found, how to reproduce it, and the version and macOS you're on. This is a volunteer project, so we can't promise a response time, but we will take every report seriously and credit you if you'd like.

## Supported versions

Only the latest release gets fixes.

## What counts

Examples of what we want to hear about:

- Ports stopping a process it should have refused or left alone
- Environment variables or command lines being written to disk or leaving the Mac
- Another program using Ports to run something or to stop processes it couldn't otherwise

## A note on downloads

Releases are currently signed ad hoc, not with an Apple Developer ID, so macOS can't confirm who built them. Each release lists SHA-256 checksums, and you can always build from source.
