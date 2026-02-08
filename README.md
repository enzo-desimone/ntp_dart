# 🌐 NTP Dart

<div align="center">

<img src="https://raw.githubusercontent.com/enzo-desimone/ntp_dart/master/example/ntp_dart.webp" alt="NTP Dart" width="400" style="border-radius: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />

**The Reliable Cross-Platform Time Synchronization Plugin for Flutter & Dart**

[![Pub Version](https://img.shields.io/pub/v/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart)
[![Pub Likes](https://img.shields.io/pub/likes/ntp_dart?style=flat-square&logo=flutter&color=02569B)](https://pub.dev/packages/ntp_dart)
[![Pub Points](https://img.shields.io/pub/points/ntp_dart?style=flat-square&logo=dart&color=0175C2)](https://pub.dev/packages/ntp_dart)
[![License](https://img.shields.io/github/license/enzo-desimone/ntp_dart?style=flat-square&color=blue)](https://github.com/enzo-desimone/ntp_dart/blob/master/LICENSE)

</div>

---

**NTP Dart** guarantees your application has access to **accurate UTC time**, regardless of valid local device settings. It seamlessly handles both cross-platform differences and network conditions to deliver reliable time data.

### 🚀 Why choose ntp_dart?

- **🛠 Cross-Platform:** Native UDP NTP on **Mobile/Desktop**, HTTP on **Web**.
- **⚡ Accurate:** Millisecond precision with **Latency Compensation**.
- **🔋 Efficient:** Built-in caching with `AccurateTime` to minimize network requests.
- **🌍 Flexible:** Configurable servers, custom Web APIs (e.g., WorldTimeAPI), and sync intervals.

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
  ntp_dart: ^1.2.0
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
final DateTime now = await AccurateTime.now();
```

**Sync (Returns cache immediately, syncs in background):**
```dart
final DateTime now = AccurateTime.nowSync();
```

**Configure Sync Interval (Default: 60 mins):**
```dart
AccurateTime.setSyncInterval(Duration(minutes: 15));
```

---

## 📘 API Reference

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

### `AccurateTime`
Singleton helper for caching and synchronization.

| Method | Description |
|:-------|:------------|
| `now({bool isUtc = false})` | Returns `Future<DateTime>`. Syncs if cache is stale. |
| `nowSync({bool isUtc = false})` | Returns `DateTime`. Background syncs if stale. |
| `nowToIsoString({bool isUtc = true})` | Returns ISO 8601 string. |
| `setSyncInterval()` | Sets the duration before the next network sync is required. |

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
