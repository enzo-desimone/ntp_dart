# 🌐 NTP Dart

<div align="center">

<img src="https://raw.githubusercontent.com/enzo-desimone/ntp_dart/master/example/ntp-dart.webp" alt="NTP Dart" width="400" style="border-radius: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />

**The Reliable Cross-Platform Time Synchronization Plugin for Flutter & Dart**

[![Pub Version](https://img.shields.io/pub/v/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart)
[![Pub Likes](https://img.shields.io/pub/likes/ntp_dart?style=flat-square&logo=flutter&color=02569B)](https://pub.dev/packages/ntp_dart)
[![Pub Points](https://img.shields.io/pub/points/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart/score)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](https://pub.dev/packages/ntp_dart/license)


</div>

---

**NTP Dart** guarantees your application has access to **accurate UTC time**, regardless of local device settings. It seamlessly handles both cross-platform differences and network conditions to deliver highly reliable time data.

### 🚀 Why choose ntp_dart?

- **🛠 Cross-Platform & Zero Conflicts:** Native UDP NTP on **Mobile/Desktop**, HTTP fallback on **Web** with **zero `intl` dependency** (never conflicts with `flutter_localizations`).
- **⚡ Extremely Accurate:** High-precision **microsecond precision** integer math, Monotonic RTT Latency Compensation, and **Multi-Sample Burst Filtering** (`samples: N`).
- **📊 Full RFC 5905 Telemetry:** Query complete `NtpResponse` diagnostics (`offset`, `roundTripDelay`, `stratum`, `leapIndicator`, `referenceId`, `rootDelay`, `rootDispersion`).
- **🛡 Robust & Secure:** Origin Timestamp anti-spoofing, Kiss-o'-Death detection, Stratum & Leap checks, Year 2036 Era 1 rollover, plus reactive **Monotonic Clock Anti-Tamper** detection (`onClockTampered` / `isTampered`).
- **🔋 Offline-First & Resilient:** Offset-based cache with multi-server automatic failover (`fallbackServers`), offline retry cooldowns, and cold-boot cache hydration (`restoreCache`).
- **⏱️ Reactive Clock Stream:** Built-in `AccurateTime.stream()` for live clocks, auctions, and TOTP timers.

---

## 📱 Platform Support

| Feature | Android | iOS | macOS | Windows | Linux | Web |
|:-------:|:-------:|:---:|:-----:|:-------:|:-----:|:---:|
| **Support** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 📦 Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  ntp_dart: ^1.5.1
```

Run installation:
```bash
flutter pub get
```

Import in your project:
```dart
import 'package:ntp_dart/ntp_dart.dart';
```

---

## 🛠 Usage

### 1️⃣ Direct Network Fetch
Get the current time directly from the server. Ideal for one-off checks.

```dart
// Standard NTP fetch (pool.ntp.org)
final DateTime now = await NtpClient().now();

// Direct fetch with full RFC 5905 telemetry (offset, RTT, stratum, etc.)
final NtpResponse response = await NtpClient().query(samples: 3);
```

#### 🌐 Web Specific Configuration
On Web, `NtpClient` natively parses RFC 1123 HTTP dates, Cloudflare Trace (`https://1.1.1.1/cdn-cgi/trace`), ISO-8601 strings, and HTTP `Date` headers, or you can customize the API endpoint and parsing logic (e.g., using **WorldTimeAPI**):

```dart
import 'dart:convert';

final customWebTime = await NtpClient(
  // Custom API Endpoint
  apiUrl: 'https://worldtimeapi.org/api/timezone/Etc/UTC',
  // Custom Response Parser
  parseResponse: (response) {
    return DateTime.parse(jsonDecode(response.body)['utc_datetime']);
  },
).now();
```

---

### 2️⃣ Synchronized & Cached Time (Recommended)
Use `AccurateTime` to maintain a synced clock without spamming network requests. It automatically re-syncs based on your interval or when device clock tampering is detected.

**Async (Checks cache, syncs if needed, supports multi-server failover & multi-sample filtering):**
```dart
// Fetch using Google NTP server (default)
final DateTime now = await AccurateTime.now();

// Fetch forcing refresh, with multi-server failover and 3-sample RTT filtering
final DateTime cloudflareTime = await AccurateTime.now(
  server: NtpServer.cloudflare,
  fallbackServers: [NtpServer.google, NtpServer.apple],
  samples: 3,
  forceRefresh: true,
  allowFallback: false,
);
```

**Sync (Returns cache immediately, syncs in background):**
```dart
final DateTime now = AccurateTime.nowSync();
```

**Configure Sync Interval (Default: 60 mins):**
```dart
AccurateTime.setSyncInterval(Duration(minutes: 15));
```

**Clear Cache:**
```dart
AccurateTime.clearCache();
```

---

### 3️⃣ Full NTP Telemetry (`NtpResponse`)
Inspect detailed network and clock diagnostics via `AccurateTime.query()` or `NtpClient().query()`:

```dart
final NtpResponse telemetry = await AccurateTime.query(samples: 3);

print('Accurate Time: ${telemetry.dateTime}');
print('Clock Offset:  ${telemetry.offset.inMilliseconds} ms');
print('Net RTT Delay: ${telemetry.roundTripDelay.inMilliseconds} ms');
print('Stratum:       ${telemetry.stratum} (Ref: ${telemetry.referenceId})');
```

---

### 4️⃣ Live Clock Stream & Anti-Tamper Detection
Build real-time UIs and detect manual system clock manipulation:

```dart
// Emit accurate time every second
AccurateTime.stream(interval: const Duration(seconds: 1), isUtc: true).listen((utcNow) {
  print('Live UTC Tick: $utcNow');
});

// React immediately if the user changes their device clock manually
AccurateTime.onClockTampered.listen((Duration skew) {
  print('⚠️ System clock tampered by ${skew.inSeconds}s! Resyncing...');
});
```

---

### 5️⃣ Offline Cold-Boot Cache Persistence
Hydrate a previously saved offset (e.g. from `SharedPreferences`) so your app has accurate time even if launched in Airplane Mode:

```dart
// On app startup:
AccurateTime.restoreCache(offset: Duration(milliseconds: savedOffsetMs));

// After a successful sync, persist AccurateTime.cachedOffset?.inMilliseconds
```

---

## 📘 API Reference

### `NtpServer`
An enum containing popular, highly reliable NTP servers:
* `NtpServer.google` (`'time.google.com'`)
* `NtpServer.cloudflare` (`'time.cloudflare.com'`)
* `NtpServer.facebook` (`'time.facebook.com'`)
* `NtpServer.microsoft` (`'time.windows.com'`)
* `NtpServer.apple` (`'time.apple.com'`)
* `NtpServer.nist` (`'time.nist.gov'`)
* `NtpServer.pool` (`'pool.ntp.org'`)

---

### `NtpClient`
The core client for fetching time directly.

| Parameter / Method | Type | Description | Default |
|:----------|:-----|:------------|:--------|
| `server` | `String` | NTP Server URL (Mobile/Desktop) | `'pool.ntp.org'` |
| `port` | `int` | NTP Port (Mobile/Desktop) | `123` |
| `timeout` | `int` | Request timeout in seconds | `5` |
| `isUtc` | `bool` | Return UTC (`true`) or Local (`false`) | `false` |
| `apiUrl` | `String?` | Time API URL (**Web Only**) | `null` (uses internal) |
| `parseResponse`| `Function?` | Parser callback (**Web Only**) | `null` |
| `now()` | `Future<DateTime>` | Fetches accurate latency-compensated `DateTime` | — |
| `query({int samples = 1})` | `Future<NtpResponse>` | Fetches full RFC 5905 telemetry with optional multi-sample filtering | — |

---

### `NtpResponse`
Telemetry returned by `NtpClient().query()` and `AccurateTime.query()`:

| Field | Type | Description |
|:------|:-----|:------------|
| `dateTime` | `DateTime` | Latency-compensated accurate time |
| `offset` | `Duration` | Measured clock offset (`serverTime - localTime`) |
| `roundTripDelay` | `Duration` | Net round-trip network delay |
| `server` | `String` | Responding server hostname or API URL |
| `stratum` | `int` | Server stratum level (`1` = primary reference) |
| `leapIndicator` | `int` | Leap second warning indicator (`0`, `1`, or `2`) |
| `referenceId` | `String?` | Reference ID (e.g. `'GOOG'`, `'LOCL'`, or IPv4) |
| `rootDelay` | `Duration` | Total round-trip delay to primary reference source |
| `rootDispersion` | `Duration` | Maximum error relative to primary reference source |

---

### `AccurateTime`
Singleton helper for caching, failover, streaming, and anti-tamper protection:

| Method / Getter | Description |
|:-------|:------------|
| `now({bool isUtc = false, NtpServer server, String? customServer, List<NtpServer>? fallbackServers, int port = 123, int timeout = 5, int samples = 1, bool forceRefresh = false, bool allowFallback = true})` | Returns `Future<DateTime>`. Syncs if cache is stale, tampered with, or force-refreshed. |
| `query({bool isUtc = false, NtpServer server, String? customServer, List<NtpServer>? fallbackServers, int port = 123, int timeout = 5, int samples = 1, bool forceRefresh = false})` | Returns `Future<NtpResponse>` with full RFC 5905 telemetry. |
| `nowSync({bool isUtc = false, NtpServer server, String? customServer, List<NtpServer>? fallbackServers, int port = 123, int timeout = 5})` | Returns `DateTime` immediately. Triggers background sync if stale. |
| `stream({Duration interval = const Duration(seconds: 1), bool isUtc = false, ...})` | Emits accurate `DateTime` ticks periodically. |
| `nowToIsoString({...})` | Returns accurate time formatted as an ISO 8601 string. |
| `restoreCache({required Duration offset, DateTime? syncTime})` | Hydrates cached offset for offline-first cold startup. |
| `setSyncInterval(Duration)` | Sets duration before next network sync is required (default 60m). |
| `setRetryCooldown(Duration)` | Sets cooldown before retrying after a failed sync (default 15s). |
| `clearCache()` | Clears cached offset, telemetry, and invalidates in-flight syncs. |
| `cachedOffset` / `lastSyncDetails` | Current cached `Duration?` offset and `NtpResponse?` telemetry. |
| `isTampered` / `onClockTampered` | Detects manual system wall-clock jumps (`> 2s`) vs monotonic clock. |
| `lastSyncTime` / `lastFailedAttempt` | Timestamps of last successful or failed synchronization. |

---

## 💡 Use Cases

- 🔐 **Authentication & TOTP:** Validate JWTs and generate 2FA codes with server-grade accuracy.
- 🎰 **Gaming & Contests:** Prevent daily-reward cheating by detecting device clock tampering via `onClockTampered`.
- ⏱️ **Live Auctions & Flash Sales:** Drive synchronized countdowns using `AccurateTime.stream()`.
- 📜 **Financial & Audit Trails:** Consistent timestamps and stratum telemetry across distributed devices.

---

## 🤝 Contributing

We welcome contributions! Please check the [issues](https://github.com/enzo-desimone/ntp_dart/issues) or submit a [PR](https://github.com/enzo-desimone/ntp_dart/pulls).

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/enzo-desimone">Enzo De Simone</a></sub>
</div>
