# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[Unreleased]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/newAM/nix-post-build-hook-queue/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/newAM/nix-post-build-hook-queue/releases/tag/v1.0.0
