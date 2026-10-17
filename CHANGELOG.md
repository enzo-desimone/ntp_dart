# Changelog

## 1.5.0
- **Full NTP Telemetry (`NtpResponse`)**: Call `NtpClient().query()` or `AccurateTime.query()` to inspect `offset`, `roundTripDelay`, `stratum`, `leapIndicator`, `referenceId`, `rootDelay`, and `rootDispersion`.
- **Multi-Sample Filtering & Server Fallbacks**: Pass `samples: 3` to select the lowest-RTT packet and `fallbackServers: [...]` to automatically failover if the primary server is unreachable.
- **Live Clock Stream & Tamper Detection**: Listen to `AccurateTime.stream()` for periodic accurate ticks and `AccurateTime.onClockTampered` (or `AccurateTime.isTampered`) to detect manual system clock changes.
- **Offline Cache Restore**: Call `AccurateTime.restoreCache(offset: ...)` on startup to hydrate a saved offset before network sync.
- **Zero-Conflict Web Parser**: Removed `intl` dependency and added built-in support for RFC 1123, Cloudflare Trace (`ts=`), ISO-8601, and HTTP `Date` headers.

## 1.4.0

- **Web Local Time & Timeout Consistency**: Fixed `isUtc: false` returning UTC instead of local `DateTime` in `ntp_web.dart` and unified timeout errors to throw `TimeoutException` across all platforms.
- **High-Performance & Zero-Lag Architecture**:
  - **Zero Post-Completion Lag (`ntp_io.dart`)**: Computed final `DateTime` *after* asynchronous socket/stream cleanup (`await subscription.cancel()`, `socket.close()`), eliminating microtask and cleanup delay bias from the measured offset.
  - **Pure 64-bit Integer Timestamp Arithmetic**: Replaced floating-point timestamp conversions with exact rounded 64-bit integer math in `writeNtpTimestamp` and `parseNtpTimestamps`, avoiding intermediate `DateTime` heap allocations on the UDP receive hot path.
  - **Monotonic RTT & Pre-compiled Web Parsers**: Used monotonic `Stopwatch` for UDP and HTTP round-trip measurements, bypassed DNS lookup via `InternetAddress.tryParse` when `server` is already an IP literal, and pre-compiled `Uri` and `DateFormat` instances in `ntp_web.dart`.
- **Monotonic Clock & Anti-Tamper Protection (`AccurateTime`)**:
  - Paired wall-clock checks with a monotonic `Stopwatch` to detect forward or backward system clock tampering (`> 2s` divergence between wall-clock and monotonic elapsed time) and immediately force resynchronization.
- **Cache Poisoning & Offline Resilience**: Fixed issue where initial network failure would lock in a `Duration.zero` offset for `syncInterval` (60m). Introduced configurable `retryCooldown` (default 15s) and ensured `lastSyncTime` only updates on successful synchronizations.
- **RFC 5905 & RFC 4330 Protocol Compliance**:
  - Implemented Origin Timestamp validation against client request Transmit Timestamp to reject spoofed, delayed, or cross-talk packets.
  - Added Leap Indicator check (`LI == 3`) and Stratum validation (`Stratum > 15`), plus Kiss-o'-Death (KoD) detection (`Stratum == 0`) with zero-copy rejection code parsing (e.g. `RATE`, `DENY`).
  - Added Year 2036 NTP Era 1 rollover handling in timestamp parsing and SNTP compatibility when `Receive Timestamp (T2)` is omitted.
- **UDP Socket Buffer Draining & Concurrency**:
  - Drained all queued UDP datagrams per `RawSocketEvent.read` in a `while` loop so truncated or spoofed packets in the OS buffer do not stall valid responses behind them.
  - Resolved race condition where duplicate datagrams could throw `Bad state: Future already completed`.
  - Added generation counter in `AccurateTime.clearCache()` to discard in-flight network responses and prevent stale cache resurrection.
- **Strict Analyzer & Expanded Test Suite**: Enabled `strict-casts`, `strict-inference`, and `strict-raw-types` in `analysis_options.yaml`, exported `NtpBase`, and expanded the test suite to 37 unit tests.

## 1.3.2
- **Documentation & Showcase**: Added package screenshot metadata in `pubspec.yaml` for pub.dev preview.

## 1.3.1
- **Unhandled Exception Fix**: Fixed uncaught asynchronous exceptions (`TimeoutException`, `SocketException`, and DNS lookup errors) leaking to `PlatformDispatcher.onError` during background synchronization triggered by `AccurateTime.nowSync()`.
- **In-Flight Request Deduplication**: Added synchronization deduplication to prevent duplicate network requests and socket allocations when `AccurateTime.nowSync()` or `AccurateTime.now()` are called concurrently.
- **Cache Management**: Enhanced `AccurateTime.clearCache()` to properly reset in-flight synchronization state.

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
