# Contributing to Ports

Thanks for helping. Bug reports, ideas, code and docs are all welcome. This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

For anything bigger than a small fix, open an issue first so we can agree on the approach.

Ports has one job. Changes should keep it:

- **Small.** The menu bar agent links only AppKit and stays near 12 MB. If a change touches `Sources/PortsApp`, measure it and put the numbers in your pull request.
- **Native.** Use Apple's controls and system colours. No custom glass, and no third-party dependencies without a good reason.
- **Careful.** Ports stops other people's work. A wrong stop is the worst bug it can have, so anything that picks or signals processes needs a test.
- **Plain.** Interface text should make sense to someone who has never heard of a process group.

## Set up

You need Xcode on macOS 13 or later.

```sh
git clone https://github.com/Open-Dev-Society/ports.git
cd ports
swift test
./build-app.sh && open dist/Ports.app
```

The tests start and stop their own throwaway servers on ports 38471–38474. They never touch anything else.

Put logic in `PortsCore` where it can be tested, and keep the three program targets thin.

## Testing interface changes by hand

Please include a screenshot, in both light and dark mode, for anything visual.

Test against throwaway servers and be careful with **Stop Idle**, which stops your real idle servers straight away.

## Pull requests

1. Branch from `main`.
2. Keep to one change, matching the style of the code around it.
3. Run `swift test` and `./build-app.sh`.
4. Add a line under `Unreleased` in [CHANGELOG.md](CHANGELOG.md) if users would notice the change.
5. Say what you tested and what you couldn't.

## Making a release

1. Update `portsVersion` in `Sources/PortsCore/Ports.swift` and move the `Unreleased` notes in `CHANGELOG.md` under the new version.
2. Merge that to `main`.
3. Tag it, `git tag v1.2.3 && git push origin v1.2.3`. The release workflow builds the app and publishes the release.
