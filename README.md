# 🌐 NTP Dart

<div align="center">

<img src="https://raw.githubusercontent.com/enzo-desimone/ntp_dart/master/example/ntp-dart.webp" alt="NTP Dart" width="400" style="border-radius: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />

**The Reliable Cross-Platform Time Synchronization Plugin for Flutter & Dart**

[![Pub Version](https://img.shields.io/pub/v/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart)
[![Pub Likes](https://img.shields.io/pub/likes/ntp_dart?style=flat-square&logo=flutter&color=02569B)](https://pub.dev/packages/ntp_dart)
[![Pub Points](https://img.shields.io/pub/points/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart)
[![License](https://img.shields.io/github/license/enzo-desimone/ntp_dart?style=flat-square&color=blue)](https://github.com/enzo-desimone/ntp_dart/blob/master/LICENSE)

</div>

---

**NTP Dart** guarantees your application has access to **accurate UTC time**, regardless of local device settings. It seamlessly handles both cross-platform differences and network conditions to deliver highly reliable time data.

### 🚀 Why choose ntp_dart?

- **🛠 Cross-Platform:** Native UDP NTP on **Mobile/Desktop**, HTTP fallback on **Web**.
- **⚡ Extremely Accurate:** High-precision **microsecond precision** integer math with Monotonic RTT Latency Compensation.
- **🛡 Robust & Secure:** Full **RFC 5905 / RFC 4330** validation (Origin Timestamp anti-spoofing, Kiss-o'-Death detection, Leap Indicator & Stratum checks, Year 2036 Era 1 rollover) plus **Monotonic Clock Anti-Tamper** detection.
- **🔋 Efficient:** Offset-based cache with offline retry cooldowns minimizes network requests while recovering automatically when connectivity returns.
- **🌍 Flexible:** Curated `NtpServer` enum (Google, Cloudflare, Apple, etc.), custom web API support, custom sync intervals, and optional grace fallbacks.

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
  ntp_dart: ^1.4.0
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
```

#### 🌐 Web Specific Configuration
On Web, you can customize the API endpoint and parsing logic (e.g., using **WorldTimeAPI**).

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
Use `AccurateTime` to maintain a synced clock without spamming network requests. It automatically re-syncs based on your interval.

**Async (Checks cache, syncs if needed):**
```dart
// Fetch using Google NTP server (default)
final DateTime now = await AccurateTime.now();

// Fetch forcing refresh, using Cloudflare, and throwing on failure instead of falling back
final DateTime cloudflareTime = await AccurateTime.now(
  server: NtpServer.cloudflare,
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
The core client for fetching time.

| Parameter | Type | Description | Default |
|:----------|:-----|:------------|:--------|
| `server` | `String` | NTP Server URL (Mobile/Desktop) | `'pool.ntp.org'` |
| `port` | `int` | NTP Port (Mobile/Desktop) | `123` |
| `timeout` | `int` | Request timeout in seconds | `5` |
| `isUtc` | `bool` | Return UTC (`true`) or Local (`false`) | `false` |
| `apiUrl` | `String?` | Time API URL (**Web Only**) | `null` (uses internal) |
| `parseResponse`| `Function?` | Parser callback (**Web Only**) | `null` |

---

### `AccurateTime`
Singleton helper for caching and synchronization.

| Method / Getter | Description |
|:-------|:------------|
| `now({bool isUtc = false, NtpServer server, String? customServer, int port = 123, int timeout = 5, bool forceRefresh = false, bool allowFallback = true})` | Returns `Future<DateTime>`. Syncs if cache is stale, tampered with, or force-refreshed. |
| `nowSync({bool isUtc = false, NtpServer server, String? customServer, int port = 123, int timeout = 5})` | Returns `DateTime` immediately. Triggers background sync if stale. |
| `nowToIsoString({bool isUtc = true, NtpServer server, String? customServer, int port = 123, int timeout = 5, bool forceRefresh = false, bool allowFallback = true})` | Returns accurate time formatted as an ISO 8601 string. |
| `setSyncInterval(Duration)` | Sets the duration before the next network sync is required (default 60m). |
| `setRetryCooldown(Duration)` | Sets cooldown period before retrying after a failed sync (default 15s). |
| `clearCache()` | Clears the cached offset and invalidates any in-flight sync. |
| `cachedOffset` | Getter for `Duration?` offset currently cached. |
| `lastSyncTime` | Getter for `DateTime?` local time of last successful sync. |
| `lastFailedAttempt` | Getter for `DateTime?` local time of last failed sync attempt. |
| `syncInterval` | Getter for `Duration` resynchronization interval. |
| `retryCooldown` | Getter for `Duration` retry cooldown duration. |

---

## 💡 Use Cases

- 🔐 **Authentication:** Validate tokens (JWT) with server-side expiry times.
- 🎰 **Gaming & Contests:** prevent cheating by bypassing device clock.
- ⏱️ **Countdowns:** Reliable timers for sales or events.
- 📜 **Audit Trails:** Consistent timestamps for logs across devices.

---

## 🤝 Contributing

We welcome contributions! Please check the [issues](https://github.com/enzo-desimone/ntp_dart/issues) or submit a [PR](https://github.com/enzo-desimone/ntp_dart/pulls).

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/enzo-desimone">Enzo De Simone</a></sub>
</div>
