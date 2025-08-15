# NTP Dart

**NTP Dart** is a lightweight and cross-platform Dart/Flutter plugin that keeps your app’s clock in sync using NTP servers (on mobile/desktop) or HTTP time endpoints (on web). It provides accurate UTC `DateTime` values for authentication, logging, and time-sensitive logic.

[![Pub Version](https://img.shields.io/pub/v/ntp_dart?style=flat-square&logo=dart)](https://pub.dev/packages/ntp_dart)
![Pub Likes](https://img.shields.io/pub/likes/ntp_dart)
![Pub Points](https://img.shields.io/pub/points/ntp_dart)
![GitHub license](https://img.shields.io/github/license/enzo-desimone/ntp_dart?style=flat-square)

---

## 📱 Supported Platforms

| Android | iOS | macOS | Web | Linux | Windows |
|:-------:|:---:|:-----:|:---:|:-----:|:-------:|
|   ✔️    | ✔️   |  ✔️   | ✔️   |  ✔️   |   ✔️    |

---

## 🔍 Overview

`ntp_dart` ensures your app maintains **accurate UTC time** across platforms.

- On **mobile/desktop**, it uses NTP protocol (UDP).
- On **web**, it uses HTTP to fetch time from a JSON endpoint like `https://worldtimeapi.org/api/timezone/etc/utc`.

This is crucial for:
- Secure token verification
- Time-based triggers
- Audit logs
- UI clocks and timers

---

## ⚙️ Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ntp_dart: ^1.0.0
```

Then install:

```bash
flutter pub get
```

Import it:

```dart
import 'package:ntp_dart/ntp_base_part.dart';
import 'package:ntp_dart/accurate_time.dart';
```

---

## 🔧 Usage

### 📡 Direct Fetch (No Caching)

Fetch fresh UTC time from the server every time:

```dart
final nowUtc = await NtpClient().now();
```

---

### 🧠 Cached Fetch with Sync Interval

Use `AccurateTime.now()` to avoid redundant requests and auto-sync periodically (default: every 60 minutes):

```dart
final nowUtc = await AccurateTime.now();
```

You can customize the interval:

```dart
AccurateTime.setSyncInterval(Duration(minutes: 30));
```
Need a synchronous value (e.g., for UI updates)? Use `AccurateTime.nowSync()`. It returns the cached UTC time immediately and
triggers a background sync if the cache is missing or stale:

```dart
final nowUtc = AccurateTime.nowSync();
```

On **web**, `AccurateTime` fetches time from a JSON endpoint (default: `https://worldtimeapi.org/...`) and caches it for the given interval.

---

## 📘 API Reference

| Method | Description |
|--------|-------------|
| `NtpClient({ String server = 'pool.ntp.org', int port = 123, int timeout = 5 })` | Constructor. Creates a new NTP client (non-Web only). |
| `Future<DateTime> NtpClient().now()` | Fetches fresh UTC time from the specified NTP server. |
| `Future<DateTime> AccurateTime.now()` | Returns cached UTC time or resynchronizes if the sync interval has expired. |
| `DateTime AccurateTime.nowSync()` | Returns cached UTC time synchronously and triggers a background sync if needed. |
| `void AccurateTime.setSyncInterval(Duration duration)` | Sets how often a new time sync should occur. Default: 60 minutes. |


---

## 💡 Common Use Cases

- ✅ **Token validation** using accurate UTC for Firebase JWTs — see [firebase_verify_token_dart](https://pub.dev/packages/firebase_verify_token_dart)
- 🕒 **Cross-platform logging** with consistent time
- 🔔 **Scheduled actions** (notifications, tasks, resets)
- 🔄 **Time-coordinated data sync**
- 🧭 **UI clocks** that stay accurate over time

---

## 🤝 Contributing

Have feedback or a fix?  
Open an [issue](https://github.com/enzo-desimone/ntp_dart/issues) or submit a [pull request](https://github.com/enzo-desimone/ntp_dart/pulls).

---

## 📃 License

MIT License. See [LICENSE](https://github.com/enzo-desimone/ntp_dart/blob/master/LICENSE).