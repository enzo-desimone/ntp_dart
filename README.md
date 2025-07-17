# NTP Dart

NTP Dart is a lightweight Dart/Flutter plugin that synchronizes your app’s clock with an NTP server or HTTP endpoint, providing accurate UTC `DateTime` for authentication, logging and other time‑sensitive operations.

[![Pub Version](https://img.shields.io/pub/v/ntp_dart?style=flat-square&logo=dart)](https://pub.dev/packages/ntp_dart)
![Pub Likes](https://img.shields.io/pub/likes/ntp_dart)
![Pub Likes](https://img.shields.io/pub/points/ntp_dart)
![Pub Likes](https://img.shields.io/pub/popularity/ntp_dart)
![GitHub license](https://img.shields.io/github/license/enzo-desimone/ntp_dart?style=flat-square)


## 📱 Supported Platforms

| Android | iOS | MacOS | Web | Linux | Windows |
|:-------:|:---:|:-----:|:---:|:-----:|:-------:|
|    ✔️   |  ✔️  |   ✔️  |  ✔️  |   ✔️  |    ✔️   |

## 🔍 Overview

NTP Dart fetches precise UTC time from NTP servers on mobile/desktop and HTTP endpoints on Web (e.g. `postman-echo.com/time/now`), ensuring your application clock remains synchronized for authentication, token verification, logging, and other time‑critical workflows.

## ⚙️ Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  ntp_dart: ^1.0.0
```

Then run:

```bash
flutter pub get
```

Import in your Dart code:

```dart
import 'package:ntp_dart/ntp_client.dart';
import 'package:ntp_dart/accurate_time.dart';
```

## 🔧 Usage

### Basic Usage

Initialize and fetch server time on every call:

```dart
final nowUtc = await NtpClient.fetchServerTime();
print(nowUtc.toIso8601String());
```

### Cached Usage with Sync Interval

Use `AccurateTime.now()` to leverage in‑memory caching and control how often a fresh time is fetched. By default it caches the last value, and you can specify a `syncInterval` to force resynchronization (default 60 muinutes of duration):

```dart
final nowUtc = await AccurateTime.now();
print(nowUtc.toIso8601String());
```

On mobile/desktop, `AccurateTime.now()` uses NTP under the hood; on Web it falls back to the HTTP endpoint, avoiding unnecessary network calls within the `syncInterval`.

## 💡 Common Use Cases

* **Accurate authentication**: Ensure JWT/Token verifications use precise UTC timestamps.
* **Consistent logging**: Normalize log entries across platforms with synchronized time.
* **Scheduled tasks**: Trigger time‑based actions (like daily notifications) reliably.
* **Data synchronization**: Coordinate data fetches/releases based on exact timestamps.
* **UI clocks**: Display a real‑time clock or countdown timer that stays in sync.

## 🤝 Contributing

Contributions welcome! Open an [issue](https://github.com/enzo-desimone/ntp_dart/issues) or submit a [pull request](https://github.com/enzo-desimone/ntp_dart/pulls).

## 📃 License

Released under MIT. See [LICENSE](https://github.com/enzo-desimone/ntp_dart/blob/main/LICENSE).
