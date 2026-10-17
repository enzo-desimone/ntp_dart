/// Synchronized NTP time caching, failover, streaming, and tamper detection.
library;

import 'dart:async';

import 'package:ntp_dart/models/libraries/libraries.dart';
import 'package:ntp_dart/models/ntp_response.dart';

/// Curated list of public NTP servers.
enum NtpServer {
  /// Google Public NTP (`time.google.com`).
  google('time.google.com'),

  /// Cloudflare NTP (`time.cloudflare.com`).
  cloudflare('time.cloudflare.com'),

  /// Meta / Facebook NTP (`time.facebook.com`).
  facebook('time.facebook.com'),

  /// Microsoft Windows NTP (`time.windows.com`).
  microsoft('time.windows.com'),

  /// Apple NTP (`time.apple.com`).
  apple('time.apple.com'),

  /// NIST Internet Time Service (`time.nist.gov`).
  nist('time.nist.gov'),

  /// NTP Pool Project (`pool.ntp.org`).
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

  /// Broadcast controller emitting clock skew durations when tampering is detected.
  static final StreamController<Duration> _tamperController =
      StreamController<Duration>.broadcast();

  /// The last measured offset (server time minus device local time).
  static Duration? _cachedOffset;

  /// The full telemetry details from the last successful synchronization.
  static NtpResponse? _lastSyncDetails;

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

  /// Returns the full [NtpResponse] telemetry from the last successful sync.
  static NtpResponse? get lastSyncDetails => _lastSyncDetails;

  /// Returns the local time when the last successful synchronization occurred.
  static DateTime get lastSyncTimeOrNull => _lastSyncTime ?? DateTime.now();

  /// Returns the local time when the last successful synchronization occurred.
  static DateTime? get lastSyncTime => _lastSyncTime;

  /// Returns the local time when a synchronization attempt last failed.
  static DateTime? get lastFailedAttempt => _lastFailedAttempt;

  /// Broadcast stream that emits the detected clock skew [Duration] whenever
  /// a manual system clock change or jump (> 2s) is detected.
  static Stream<Duration> get onClockTampered => _tamperController.stream;

  /// Returns `true` if the local device wall-clock has diverged from the
  /// monotonic clock by more than 2 seconds since the last successful sync.
  static bool get isTampered {
    final syncTime = _lastSyncTime;
    final syncElapsed = _lastSyncElapsed;
    if (syncTime == null || syncElapsed == null) return false;

    final monoElapsed = _stopwatch.elapsed - syncElapsed;
    final wallElapsed = DateTime.now().difference(syncTime);
    return (wallElapsed - monoElapsed).abs() > _maxClockSkew;
  }

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
    final skew = wallElapsed - monoElapsed;

    // If wall-clock delta diverges from monotonic delta, the device clock jumped or was tampered with.
    if (skew.abs() > _maxClockSkew) {
      if (_tamperController.hasListener) {
        _tamperController.add(skew);
      }
      return false;
    }

    if (wallElapsed.isNegative || wallElapsed > _syncInterval) {
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
  /// You can also provide a custom raw server URL string via [customServer],
  /// or a list of [fallbackServers] to try automatically if the primary server fails.
  ///
  /// When [samples] > 1, performs multi-sample clock filtering and selects the
  /// measurement with the lowest round-trip delay.
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
    List<NtpServer>? fallbackServers,
    int port = 123,
    int timeout = 5,
    int samples = 1,
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
          servers: _buildServerList(server, customServer, fallbackServers),
          port: port,
          timeout: timeout,
          samples: samples,
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

  /// Queries accurate time and returns a full [NtpResponse] with telemetry
  /// (offset, round-trip delay, stratum, referenceId, etc.).
  ///
  /// Uses cached telemetry if the cache is fresh and [forceRefresh] is `false`,
  /// updating [NtpResponse.dateTime] to the current instant.
  static Future<NtpResponse> query({
    bool isUtc = false,
    NtpServer server = NtpServer.google,
    String? customServer,
    List<NtpServer>? fallbackServers,
    int port = 123,
    int timeout = 5,
    int samples = 1,
    bool forceRefresh = false,
  }) async {
    final nowLocal = DateTime.now();
    final hasFreshCache = _isCacheFresh(nowLocal) && _lastSyncDetails != null;

    if (forceRefresh || !hasFreshCache) {
      await _syncNtpTime(
        servers: _buildServerList(server, customServer, fallbackServers),
        port: port,
        timeout: timeout,
        samples: samples,
      );
    }

    final details = _lastSyncDetails!;
    final currentCorrected =
        DateTime.now().add(_cachedOffset ?? details.offset);
    return NtpResponse(
      dateTime: isUtc ? currentCorrected.toUtc() : currentCorrected.toLocal(),
      offset: details.offset,
      roundTripDelay: details.roundTripDelay,
      server: details.server,
      stratum: details.stratum,
      leapIndicator: details.leapIndicator,
      referenceId: details.referenceId,
      rootDelay: details.rootDelay,
      rootDispersion: details.rootDispersion,
    );
  }

  /// Emits a continuous stream of accurate [DateTime] values at [interval].
  ///
  /// Ideal for live clocks, auction timers, and TOTP countdowns. Automatically
  /// triggers background resynchronization if the cache expires or if system
  /// clock tampering is detected.
  static Stream<DateTime> stream({
    Duration interval = const Duration(seconds: 1),
    bool isUtc = false,
    NtpServer server = NtpServer.google,
    String? customServer,
    int port = 123,
    int timeout = 5,
  }) async* {
    yield await now(
      isUtc: isUtc,
      server: server,
      customServer: customServer,
      port: port,
      timeout: timeout,
    );

    yield* Stream.periodic(interval, (_) {
      return nowSync(
        isUtc: isUtc,
        server: server,
        customServer: customServer,
        port: port,
        timeout: timeout,
      );
    });
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
    List<NtpServer>? fallbackServers,
    int port = 123,
    int timeout = 5,
  }) {
    final nowLocal = DateTime.now();
    final shouldSync = !_isCacheFresh(nowLocal);

    if (shouldSync && !_isInCooldown() && _ongoingSync == null) {
      _triggerBackgroundSync(
        servers: _buildServerList(server, customServer, fallbackServers),
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

  static List<String> _buildServerList(
    NtpServer primary,
    String? customServer,
    List<NtpServer>? fallbackServers,
  ) {
    final result = <String>[customServer ?? primary.url];
    if (fallbackServers != null) {
      for (final fb in fallbackServers) {
        if (!result.contains(fb.url)) {
          result.add(fb.url);
        }
      }
    }
    return result;
  }

  /// Triggers a background sync, safely capturing any error so it does not
  /// leak as an unhandled asynchronous exception to the root zone.
  static void _triggerBackgroundSync({
    required List<String> servers,
    required int port,
    required int timeout,
  }) {
    unawaited(
      _syncNtpTime(
        servers: servers,
        port: port,
        timeout: timeout,
        samples: 1,
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
    List<NtpServer>? fallbackServers,
    int port = 123,
    int timeout = 5,
    int samples = 1,
    bool forceRefresh = false,
    bool allowFallback = true,
  }) async {
    final time = await now(
      isUtc: isUtc,
      server: server,
      customServer: customServer,
      fallbackServers: fallbackServers,
      port: port,
      timeout: timeout,
      samples: samples,
      forceRefresh: forceRefresh,
      allowFallback: allowFallback,
    );
    return time.toIso8601String();
  }

  /// Restores a previously saved [offset] (e.g. from `SharedPreferences` or
  /// secure storage) to enable offline-first accuracy on application startup.
  static void restoreCache({
    required Duration offset,
    DateTime? syncTime,
  }) {
    final nowLocal = DateTime.now();
    _cachedOffset = offset;
    _lastSyncTime = syncTime ?? nowLocal;
    _lastSyncElapsed = _stopwatch.elapsed;
    _lastSyncDetails = NtpResponse(
      dateTime: nowLocal.add(offset),
      offset: offset,
      roundTripDelay: Duration.zero,
      server: 'cache',
      referenceId: 'CACH',
    );
  }

  /// Fetches the offset from the NTP server(s) and updates the cache.
  ///
  /// Deduplicates concurrent synchronization requests by reusing the in-flight
  /// future if one is already in progress.
  static Future<void> _syncNtpTime({
    required List<String> servers,
    required int port,
    required int timeout,
    required int samples,
  }) {
    final ongoing = _ongoingSync;
    if (ongoing != null) {
      return ongoing;
    }

    final syncFuture = _performSyncNtpTime(
      servers: servers,
      port: port,
      timeout: timeout,
      samples: samples,
    );

    final future = syncFuture.whenComplete(() {
      _ongoingSync = null;
    });

    _ongoingSync = future;
    return future;
  }

  static Future<void> _performSyncNtpTime({
    required List<String> servers,
    required int port,
    required int timeout,
    required int samples,
  }) async {
    final generation = _syncGeneration;
    Object? lastError;
    StackTrace? lastStack;

    for (final host in servers) {
      try {
        final client = _createNtpClient(
          server: host,
          port: port,
          timeout: timeout,
        );
        final response = await client.query(samples: samples);
        final nowLocal = DateTime.now();

        if (generation != _syncGeneration) {
          return;
        }

        _cachedOffset = response.dateTime.difference(nowLocal);
        _lastSyncDetails = NtpResponse(
          dateTime: response.dateTime,
          offset: _cachedOffset!,
          roundTripDelay: response.roundTripDelay,
          server: response.server,
          stratum: response.stratum,
          leapIndicator: response.leapIndicator,
          referenceId: response.referenceId,
          rootDelay: response.rootDelay,
          rootDispersion: response.rootDispersion,
        );
        _lastSyncTime = nowLocal;
        _lastSyncElapsed = _stopwatch.elapsed;
        _lastFailedAttempt = null;
        _lastFailedElapsed = null;
        return;
      } catch (e, s) {
        lastError = e;
        lastStack = s;
      }
    }

    if (generation == _syncGeneration) {
      _lastFailedAttempt = DateTime.now();
      _lastFailedElapsed = _stopwatch.elapsed;
      _cachedOffset ??= Duration.zero;
    }

    Error.throwWithStackTrace(
      lastError ?? Exception('Failed to synchronize NTP time'),
      lastStack ?? StackTrace.current,
    );
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
    _lastSyncDetails = null;
    _lastSyncTime = null;
    _lastSyncElapsed = null;
    _lastFailedAttempt = null;
    _lastFailedElapsed = null;
    _ongoingSync = null;
  }
}
