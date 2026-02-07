# Changelog

## 1.2.0
- Added `apiUrl` and `parseResponse` parameters to `NtpBase` to allow custom API endpoints and response parsing on Web.
- Implemented latency compensation for both Web and IO.
- Improved NTP timestamp parsing in IO to support millisecond precision.
- Added timeout support for Web NTP requests.
- Updated dependencies: `http` to ^1.6.0 and `intl` to ^0.20.2.

## 1.1.1
- Added `AccurateTime.nowSync()` method to provide a synchronous time value, useful for UI rendering while the first sync is in progress.
- Change logic for conditional import based on platform. No breaking API changes.
- Updated `http` dependency (previously 1.4.0) to 1.5.0.
- Refreshed README and examples to reflect the new platform setup and usage notes.

## 1.0.2
- Update documentation

## 1.0.1
- Enable flutter web wasm compatibility

## 1.0.0
- Publish package
