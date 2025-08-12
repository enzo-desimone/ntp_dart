import 'dart:async';

import 'package:ntp_dart/ntp_dart.dart';

/// A static class to manage accurate UTC time using HTTP synchronization and local caching.
class AccurateTime {
  /// The last fetched accurate UTC time from the NTP server.
  static DateTime? _cachedUtcTime;

  /// The local time when the last NTP sync occurred.
  static DateTime? _lastNtpSync;

  /// The interval at which the time should be resynchronized.
  static Duration _syncInterval = const Duration(minutes: 60);

  /// NTP client instance (customizable if needed)
  static final NtpClient _ntpClient = NtpClient();

  /// Returns the current accurate UTC time.
  ///
  /// If the cached time is outdated or not initialized, it fetches the time
  /// from an NTP server and adjusts the result based on local time drift.
  ///
  /// Returns a [DateTime] in UTC.
  static Future<DateTime> now() async {
    var now = DateTime.now();
    if (_cachedUtcTime == null ||
        _lastNtpSync == null ||
        now.difference(_lastNtpSync!) > _syncInterval) {
      await _syncNtpTime();
      now = DateTime.now();
    }

    final timeDifference = now.difference(_lastNtpSync!);
    return _cachedUtcTime!.add(timeDifference);
  }

  /// Returns the current accurate UTC time as an ISO 8601 string.
  static Future<String> nowToIsoString() async {
    return (await now()).toIso8601String();
  }

  /// Fetches the current UTC time from the NTP server and updates the cache.
  ///
  /// If the request fails, the cached time will not be updated.
  static Future<void> _syncNtpTime() async {
    try {
      final ntpTime = await _ntpClient.now();
      _lastNtpSync = DateTime.now();
      _cachedUtcTime = ntpTime;
    } catch (e) {
      _cachedUtcTime = DateTime.now().toUtc();
    }
  }

  /// Updates the duration used to determine when to resync the time.
  ///
  /// The [newInterval] defines the maximum age of the cached time before a
  /// new synchronization is triggered.
  static void setSyncInterval(Duration newInterval) {
    _syncInterval = newInterval;
  }
}
