# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.2.4 - 2025-06-14

### Added

- Added some tests

### Changed

- Add more documentation

## v0.2.3 - 2025-06-14

### Fixed

- Fix issue when attempting to generate a rate limiter instance name from a plain atom (instead of a module)

- More documentation cleanup

## v0.2.2 - 2025-06-13

### Changed

- Add more documentation

## v0.2.1 - 2025-06-13

### Changed

- Add more documentation

## v0.2.0 - 2025-06-13

### Added

- Proper documentation and usage instructions

- Helper functions for removing boilerplate and making it easier to work with the application:
  - `RateLimiterMan.start_task_supervisor/0` and `RateLimiterMan.start_rate_limiter/0`

### Changed

- Removed unnecessary config values when adding a rate limiter to the supervision tree

- The logger is now configurable when setting up the rate limiter (via the `:rate_limiter_logger_level` key), and may also be overridden by passing the `:logger_level` as an option when calling `RateLimiter.make_request/4`.

### Fixed

- Remove hardcoded OTP app name so that this project can actually be reused in different applications. 🙃

## v0.1.1 - 2025-04-29

### Changed

- Modify Hex project description

## v0.1.0 - 2025-04-19

### Added

- Initial release

## v0.1.0 - 2025-04-19

### Added

- Initial release
