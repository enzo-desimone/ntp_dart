import 'dart:async';

import 'package:ntp_dart/models/libraries/libraries.dart';

/// Curated list of public NTP servers.
enum NtpServer {
  google('time.google.com'),
  cloudflare('time.cloudflare.com'),
  facebook('time.facebook.com'),
  microsoft('time.windows.com'),
  apple('time.apple.com'),
  nist('time.nist.gov'),
  pool('pool.ntp.org');

  const NtpServer(this.url);

  /// The URL of the NTP server.
  final String url;
}

/// A static class to manage accurate UTC time using HTTP/UDP synchronization
/// and local caching.
class AccurateTime {
  /// The last measured offset (server time minus device local time).
  static Duration? _cachedOffset;

  /// The local time when the last successful NTP sync occurred.
  static DateTime? _lastSyncTime;

  /// The interval at which the time should be resynchronized.
  static Duration _syncInterval = const Duration(minutes: 60);

  /// Factory function to create an [NtpClient] instance.
  /// Primarily used to inject mock/stub clients during unit testing.
  static NtpClient Function({
    String server,
    int port,
    int timeout,
    bool isUtc,
  })? ntpClientFactory;

  /// NTP client instance (customizable if needed)
  static NtpClient _createNtpClient({
    String server = 'pool.ntp.org',
    int port = 123,
    int timeout = 5,
    bool isUtc = true,
  }) {
    if (ntpClientFactory != null) {
      return ntpClientFactory!(
        server: server,
        port: port,
        timeout: timeout,
        isUtc: isUtc,
      );
    }
    return NtpClient(
      server: server,
      port: port,
      timeout: timeout,
      isUtc: isUtc,
    );
  }

  /// The in-flight synchronization future, if any.
  static Future<void>? _ongoingSync;

  /// Curated list of public NTP servers.
  static Duration get syncInterval => _syncInterval;

  /// Returns the current accurate cached offset (server time - local time).
  static Duration? get cachedOffset => _cachedOffset;

  /// Returns the local time when the last successful synchronization occurred.
  static DateTime? get lastSyncTime => _lastSyncTime;

  /// Returns the current accurate time.
  ///
  /// If [isUtc] is `true`, returns the time in UTC.
  /// If [isUtc] is `false` (default), returns the time in the local time zone.
  ///
  /// If [server] is specified (defaults to [NtpServer.google]), it queries that server.
  /// You can also provide a custom raw server URL string via [customServer].
  ///
  /// If [forceRefresh] is `true`, a network request is forced even if a fresh
  /// cache exists.
  ///
  /// If [allowFallback] is `true` (default), returns the local device time on failure
  /// instead of throwing an error.
  static Future<DateTime> now({
    bool isUtc = false,
    NtpServer server = NtpServer.google,
    String? customServer,
    int port = 123,
    int timeout = 5,
    bool forceRefresh = false,
    bool allowFallback = true,
  }) async {
    final nowLocal = DateTime.now();

    final hasFreshCache = _cachedOffset != null &&
        _lastSyncTime != null &&
        nowLocal.difference(_lastSyncTime!) <= _syncInterval;

    if (forceRefresh || !hasFreshCache) {
      try {
        await _syncNtpTime(
          server: customServer ?? server.url,
          port: port,
          timeout: timeout,
        );
      } catch (e) {
        if (!allowFallback) {
          rethrow;
        }
      }
    }

    final corrected = DateTime.now().add(_cachedOffset ?? Duration.zero);
    return isUtc ? corrected.toUtc() : corrected.toLocal();
  }

  /// Returns the current accurate time synchronously using the cached offset.
  ///
  /// If [isUtc] is `true`, returns the time in UTC.
  /// If [isUtc] is `false` (default), returns the time in the local time zone.
  ///
  /// If the cache has not been initialized yet, it triggers an asynchronous
  /// synchronization in the background and returns the local system time.
  ///
  /// If the cached value is older than the configured sync interval, a
  /// background resynchronization is triggered while still returning the
  /// computed time based on the cached offset.
  static DateTime nowSync({
    bool isUtc = false,
    NtpServer server = NtpServer.google,
    String? customServer,
    int port = 123,
    int timeout = 5,
  }) {
    final nowLocal = DateTime.now();

    if (_cachedOffset == null || _lastSyncTime == null) {
      _triggerBackgroundSync(
        server: customServer ?? server.url,
        port: port,
        timeout: timeout,
      );
      return isUtc ? nowLocal.toUtc() : nowLocal;
    }

    if (nowLocal.difference(_lastSyncTime!) > _syncInterval) {
      _triggerBackgroundSync(
        server: customServer ?? server.url,
        port: port,
        timeout: timeout,
      );
    }

    final corrected = nowLocal.add(_cachedOffset!);
    return isUtc ? corrected.toUtc() : corrected.toLocal();
  }

  /// Triggers a background sync, safely capturing any error so it does not
  /// leak as an unhandled asynchronous exception to the root zone.
  static void _triggerBackgroundSync({
    required String server,
    required int port,
    required int timeout,
  }) {
    unawaited(
      _syncNtpTime(
        server: server,
        port: port,
        timeout: timeout,
      ).catchError((Object error, StackTrace stackTrace) {
        // Silently catch background synchronization errors (e.g. timeouts or
        // unreachable hosts) to prevent unhandled asynchronous exceptions
        // from bubbling up to PlatformDispatcher.onError.
      }),
    );
  }

  /// Returns the current accurate time as an ISO 8601 string.
  ///
  /// [isUtc] defaults to `true` (UTC).
  static Future<String> nowToIsoString({bool isUtc = true}) =>
      now(isUtc: isUtc).then((time) => time.toIso8601String());

  /// Fetches the offset from the NTP server and updates the cache.
  ///
  /// Deduplicates concurrent synchronization requests by reusing the in-flight
  /// future if one is already in progress.
  static Future<void> _syncNtpTime({
    required String server,
    required int port,
    required int timeout,
  }) {
    final ongoing = _ongoingSync;
    if (ongoing != null) {
      return ongoing;
    }

    final syncFuture = _performSyncNtpTime(
      server: server,
      port: port,
      timeout: timeout,
    );

    final future = syncFuture.whenComplete(() {
      _ongoingSync = null;
    });

    _ongoingSync = future;
    return future;
  }

  static Future<void> _performSyncNtpTime({
    required String server,
    required int port,
    required int timeout,
  }) async {
    try {
      final client = _createNtpClient(
        server: server,
        port: port,
        timeout: timeout,
      );
      final serverTime = await client.now();
      final nowLocal = DateTime.now();
      _cachedOffset = serverTime.difference(nowLocal);
      _lastSyncTime = nowLocal;
    } catch (e) {
      if (_cachedOffset == null) {
        _cachedOffset = Duration.zero;
        _lastSyncTime = DateTime.now();
      }
      rethrow;
    }
  }

  /// Updates the duration used to determine when to resync the time.
  ///
  /// [newInterval] specifies the minimum duration between consecutive
  /// synchronizations.
  static void setSyncInterval(Duration newInterval) {
    _syncInterval = newInterval;
  }

  /// Clears the cached NTP offset and synchronization time.
  static void clearCache() {
    _cachedOffset = null;
    _lastSyncTime = null;
    _ongoingSync = null;
  }
}
