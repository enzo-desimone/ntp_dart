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
  // Private constructor to prevent instantiation.
  AccurateTime._();

  /// Monotonic clock used to measure intervals and detect system clock tampering.
  static final Stopwatch _stopwatch = Stopwatch()..start();

  /// Maximum tolerated divergence between wall-clock and monotonic elapsed time
  /// before assuming the system clock was manually altered or jumped.
  static const Duration _maxClockSkew = Duration(seconds: 2);

  /// The last measured offset (server time minus device local time).
  static Duration? _cachedOffset;

  /// The local time when the last successful NTP sync occurred.
  static DateTime? _lastSyncTime;

  /// Monotonic elapsed duration when the last successful NTP sync occurred.
  static Duration? _lastSyncElapsed;

  /// The local time when a synchronization attempt last failed.
  static DateTime? _lastFailedAttempt;

  /// Monotonic elapsed duration when a synchronization attempt last failed.
  static Duration? _lastFailedElapsed;

  /// The interval at which the time should be resynchronized.
  static Duration _syncInterval = const Duration(minutes: 60);

  /// The cooldown duration before retrying after a failed sync.
  static Duration _retryCooldown = const Duration(seconds: 15);

  /// Monotonically increasing generation to invalidate in-flight syncs on clearCache.
  static int _syncGeneration = 0;

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

  /// Interval between scheduled resynchronizations.
  static Duration get syncInterval => _syncInterval;

  /// The cooldown duration before retrying after a failed sync.
  static Duration get retryCooldown => _retryCooldown;

  /// Updates the cooldown duration before retrying after a failed sync.
  static void setRetryCooldown(Duration duration) {
    _retryCooldown = duration;
  }

  /// Returns the current accurate cached offset (server time - local time).
  static Duration? get cachedOffset => _cachedOffset;

  /// Returns the local time when the last successful synchronization occurred.
  static DateTime? get lastSyncTime => _lastSyncTime;

  /// Returns the local time when a synchronization attempt last failed.
  static DateTime? get lastFailedAttempt => _lastFailedAttempt;

  /// Checks whether the cached offset is present, within [_syncInterval],
  /// and free of system wall-clock tampering relative to the monotonic clock.
  static bool _isCacheFresh(DateTime nowLocal) {
    final offset = _cachedOffset;
    final syncTime = _lastSyncTime;
    final syncElapsed = _lastSyncElapsed;
    if (offset == null || syncTime == null || syncElapsed == null) {
      return false;
    }

    final monoElapsed = _stopwatch.elapsed - syncElapsed;
    if (monoElapsed.isNegative || monoElapsed > _syncInterval) {
      return false;
    }

    final wallElapsed = nowLocal.difference(syncTime);
    if (wallElapsed.isNegative || wallElapsed > _syncInterval) {
      return false;
    }

    // If wall-clock delta diverges from monotonic delta, the device clock jumped or was tampered with.
    if ((wallElapsed - monoElapsed).abs() > _maxClockSkew) {
      return false;
    }

    return true;
  }

  /// Checks whether a failed attempt occurred within [_retryCooldown] using the monotonic clock.
  static bool _isInCooldown() {
    final failedElapsed = _lastFailedElapsed;
    if (failedElapsed == null) return false;
    return (_stopwatch.elapsed - failedElapsed) < _retryCooldown;
  }

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
    final hasFreshCache = _isCacheFresh(nowLocal);
    final hasOngoingSync = _ongoingSync != null;
    final inCooldown = !hasOngoingSync && !forceRefresh && _isInCooldown();

    if (forceRefresh || (!hasFreshCache && !inCooldown) || hasOngoingSync) {
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
    final shouldSync = !_isCacheFresh(nowLocal);

    if (shouldSync && !_isInCooldown() && _ongoingSync == null) {
      _triggerBackgroundSync(
        server: customServer ?? server.url,
        port: port,
        timeout: timeout,
      );
    }

    final offset = _cachedOffset;
    if (offset == null) {
      return isUtc ? nowLocal.toUtc() : nowLocal;
    }

    final corrected = nowLocal.add(offset);
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
  static Future<String> nowToIsoString({
    bool isUtc = true,
    NtpServer server = NtpServer.google,
    String? customServer,
    int port = 123,
    int timeout = 5,
    bool forceRefresh = false,
    bool allowFallback = true,
  }) async {
    final time = await now(
      isUtc: isUtc,
      server: server,
      customServer: customServer,
      port: port,
      timeout: timeout,
      forceRefresh: forceRefresh,
      allowFallback: allowFallback,
    );
    return time.toIso8601String();
  }

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
    final generation = _syncGeneration;

    try {
      final client = _createNtpClient(
        server: server,
        port: port,
        timeout: timeout,
      );
      final serverTime = await client.now();
      final nowLocal = DateTime.now();

      if (generation != _syncGeneration) {
        return;
      }

      _cachedOffset = serverTime.difference(nowLocal);
      _lastSyncTime = nowLocal;
      _lastSyncElapsed = _stopwatch.elapsed;
      _lastFailedAttempt = null;
      _lastFailedElapsed = null;
    } catch (e) {
      if (generation == _syncGeneration) {
        _lastFailedAttempt = DateTime.now();
        _lastFailedElapsed = _stopwatch.elapsed;
        _cachedOffset ??= Duration.zero;
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
    _syncGeneration++;
    _cachedOffset = null;
    _lastSyncTime = null;
    _lastSyncElapsed = null;
    _lastFailedAttempt = null;
    _lastFailedElapsed = null;
    _ongoingSync = null;
  }
}
