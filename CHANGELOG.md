# Changelog

Notable changes to Ports. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-02

First public release.

### Added

- Menu bar item with a memory meter, about 12 MB in the background.
- Panel with a memory budget, one tile per server, a legend and light and dark modes.
- Real memory figures from `phys_footprint`, the number Activity Monitor shows.
- Dev servers only by default, with the project, who started it and whether it's open to the network.
- Stopping a whole server by process group, with a confirmation.
- Stop Idle for every server up three hours or more with nothing connected.
- Undo for five seconds after a stop.
- Memory budget that starts at a quarter of the Mac's memory.
- Open at Login, turned on the first time Ports runs from Applications.
- `ports` terminal command, inside the app.
- Universal build for Apple silicon and Intel.

[Unreleased]: https://github.com/Open-Dev-Society/ports/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Open-Dev-Society/ports/releases/tag/v0.1.0
