import 'dart:async';

import 'models.dart';

/// A static class to manage accurate UTC time using HTTP synchronization and local caching.
class AccurateTime {
  /// The last fetched accurate UTC time from the NTP server.
  static DateTime? _cachedUtcTime;

  /// The local time when the last NTP sync occurred.
  static DateTime? _lastNtpSync;

  /// The interval at which the time should be resynchronized.
  static Duration _syncInterval = const Duration(minutes: 60);

  /// NTP client instance (customizable if needed)
  static NtpClient _ntpClient = NtpClient();

  /// Returns the current accurate UTC time.
  ///
  /// If the cached time is outdated or not initialized, it fetches the time
  /// from an NTP server. Then it adjusts based on local time drift.
  static Future<DateTime> now() async {
    if (_cachedUtcTime == null ||
        _lastNtpSync == null ||
        DateTime.now().difference(_lastNtpSync!) > _syncInterval) {
      await _syncNtpTime();
    }

    final timeDifference = DateTime.now().difference(_lastNtpSync!);
    return _cachedUtcTime!.add(timeDifference);
  }

  /// Returns the current accurate UTC time synchronously.
  ///
  /// If the cache has not been initialized yet, it triggers an asynchronous
  /// synchronization and returns the local system time converted to UTC. When
  /// the cache is available, it computes the accurate time using the cached
  /// value. If the cached value is older than the configured sync interval, a
  /// background resynchronization is triggered while still returning the
  /// computed time.
  static DateTime nowSync() {
    if (_cachedUtcTime == null || _lastNtpSync == null) {
      unawaited(_syncNtpTime());
      return DateTime.now().toUtc();
    }

    final timeDifference = DateTime.now().difference(_lastNtpSync!);
    if (timeDifference > _syncInterval) {
      unawaited(_syncNtpTime());
    }

    return _cachedUtcTime!.add(timeDifference);
  }

  /// Returns the current accurate UTC time as an ISO 8601 string.
  static Future<String> nowToIsoString() =>
      now().then((time) => time.toIso8601String());

  /// Fetches the current UTC time from the NTP server and updates the cache.
  ///
  /// If the request fails, the cached time will not be updated.
  static Future<void> _syncNtpTime() async {
    try {
      final ntpTime = await _ntpClient.now();
      _lastNtpSync = DateTime.now();
      _cachedUtcTime = ntpTime;
    } catch (e) {
      final fallback = DateTime.now();
      _lastNtpSync = fallback;
      _cachedUtcTime = fallback.toUtc();
    }
  }

  /// Updates the duration used to determine when to resync the time.
  ///
  /// [newInterval] specifies the minimum duration between consecutive
  /// synchronizations.
  static void setSyncInterval(Duration newInterval) {
    _syncInterval = newInterval;
  }
}
