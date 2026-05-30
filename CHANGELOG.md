# Changelog

## 1.3.0
- **Refactored Cache**: Transitioned `AccurateTime` cache to use time offset calculation (`cachedOffset`) rather than absolute datetime tracking, boosting reliability and simplifying local drift corrections.
- **Microsecond Precision**: Enhanced UDP packet timestamp parsing and math to support full microsecond accuracy (matching Dart's `DateTime` resolution).
- **Socket and Stream Safety**: Rewrote UDP networking in `ntp_io.dart` with robust `try-finally` blocks to guarantee socket closure and prevent resource leakages on bad networks or cancellation.
- **RFC 5905 Security Compliance**: Implemented transmit timestamp writing and randomized low-order bits on client request packets to resist off-path spoofing and replay attacks.
- **NtpServer Enum**: Introduced `NtpServer` enum offering curated, ultra-reliable servers (`google`, `cloudflare`, `apple`, `microsoft`, `nist`, `pool`).
- **Flexible Fallbacks**: Added `allowFallback` and `forceRefresh` to `AccurateTime.now()`.
- **Test Suite**: Introduced a comprehensive unit testing framework in `test/ntp_dart_test.dart`.

## 1.2.1
- Added `isUtc` parameter (default `false`) to `AccurateTime.now()`, `AccurateTime.nowSync()`, and `AccurateTime.nowToIsoString()`.
- Fixed caching logic in `AccurateTime` to always store UTC and convert to local only when requested.

## 1.2.0
- Added `apiUrl` and `parseResponse` parameters to `NtpBase` to allow custom API endpoints and response parsing on Web.
- Added `isUtc` parameter (default `false`) to control whether to return UTC or Local time.
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
