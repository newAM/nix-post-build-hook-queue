# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Removed

- Removed the `services.nix-post-build-hook-queue.package` option.
- Removed the `services.nix-post-build-hook-queue.user` and `services.nix-post-build-hook-queue.group` options, the service now runs as a dynamic user.

## [1.1.0] - 2026-02-01

### Added

- Added an upload queue status under `/run/nix-post-build-hook-queue/uploading/` by [@SecBear] in [#113].
- Added an actual queue and multiple workers by [@yuyuyureka] in [#107].

[@yuyuyureka]: https://github.com/yuyuyureka
[@SecBear]: https://github.com/SecBear
[#107]: https://github.com/newAM/nix-post-build-hook-queue/pull/107
[#113]: https://github.com/newAM/nix-post-build-hook-queue/pull/113

## [1.0.3] - 2025-10-05

### Fixed

- Fixed excessive CPU utilization in the `post-build-hook-queue` from a busy loop.

## [1.0.2] - 2025-07-09

### Fixed

- Fixed the "Unknown key 'StartLimitIntervalSec' in section [Service], ignoring" warning.

## [1.0.1] - 2025-02-15

### Fixed

- Fixed `start-limit-hit` failure when doing many small builds.

## [1.0.0] - 2025-02-08

Initial release.

[Unreleased]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/newAM/nix-post-build-hook-queue/releases/tag/v1.0.0
