/// Telemetry model for NTP synchronization responses.
library;

/// Represents a detailed response from an NTP synchronization query.
///
/// Contains the compensated [dateTime] along with full RFC 5905 telemetry
/// such as [offset], [roundTripDelay], [stratum], [leapIndicator],
/// [rootDelay], [rootDispersion], and [referenceId].
class NtpResponse {
  /// Creates an immutable [NtpResponse] instance.
  const NtpResponse({
    required this.dateTime,
    required this.offset,
    required this.roundTripDelay,
    required this.server,
    this.stratum = 1,
    this.leapIndicator = 0,
    this.referenceId,
    this.rootDelay = Duration.zero,
    this.rootDispersion = Duration.zero,
  });

  /// The accurate, latency-compensated time.
  final DateTime dateTime;

  /// The clock offset ($\theta$) between the server and the local device clock
  /// (`serverTime - localTime`).
  final Duration offset;

  /// The net network round-trip delay ($\delta$).
  final Duration roundTripDelay;

  /// The server hostname, IP, or API endpoint that provided the response.
  final String server;

  /// The NTP server stratum level (1 = primary reference, 2–15 = secondary).
  final int stratum;

  /// The leap second indicator (0 = no warning, 1 = +1s, 2 = -1s).
  final int leapIndicator;

  /// The 4-character ASCII reference identifier (for stratum 1, e.g. `'GOOG'`,
  /// `'GPS'`) or IPv4 reference address string (for stratum >= 2).
  final String? referenceId;

  /// The total round-trip delay to the primary reference source.
  final Duration rootDelay;

  /// The maximum error relative to the primary reference source.
  final Duration rootDispersion;

  @override
  String toString() =>
      'NtpResponse(dateTime: $dateTime, offset: ${offset.inMicroseconds}µs, '
      'rtt: ${roundTripDelay.inMicroseconds}µs, server: $server, '
      'stratum: $stratum, refId: $referenceId)';
}
