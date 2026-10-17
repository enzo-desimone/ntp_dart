/// HTTP-based NTP client implementation for Web and WASM environments.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:ntp_dart/models/libraries/ntp_base.dart';
import 'package:ntp_dart/models/ntp_response.dart';

/// A web-based implementation of an NTP (Network Time Protocol) client.
///
/// This implementation retrieves the current server time via an HTTP API
/// rather than using a raw UDP socket (which is not available in web
/// environments).
///
/// By default, it queries the Postman Echo `/time/now` endpoint, which
/// returns the current GMT time as a string (e.g. `"Thu, 17 Jul 2025 12:34:56 GMT"`).
/// It also natively supports Cloudflare Trace (`ts=...`), ISO-8601 strings,
/// and standard HTTP `Date` headers without requiring `package:intl`.
class NtpClient extends NtpBase {
  /// Creates a new [NtpClient] instance with optional configuration parameters.
  ///
  /// Although [server] and [port] are accepted for API compatibility with
  /// other platforms, they are ignored in this web implementation.
  /// [timeout] is used as the HTTP request timeout.
  const NtpClient({
    super.server,
    super.port,
    super.timeout,
    super.apiUrl,
    super.parseResponse,
    super.isUtc,
  });

  /// The base URL of the default time API endpoint.
  static const String _api = 'https://postman-echo.com/time/now';

  /// Pre-parsed default URI to avoid repeated parsing on every call.
  static final Uri _defaultUri = Uri.parse(_api);

  static const Map<String, int> _months = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  static final RegExp _rfc1123RegExp = RegExp(
    r'^[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+(?:GMT|UTC)$',
  );

  static final RegExp _cloudflareTraceRegExp = RegExp(
    r'(?:^|\n)ts=(\d+)(?:\.(\d+))?(?:\n|$)',
  );

  /// Fetches the current server time from the configured HTTP API.
  @override
  Future<DateTime> now() async {
    final response = await query();
    return response.dateTime;
  }

  /// Queries the configured HTTP time endpoint and returns a full [NtpResponse].
  ///
  /// When [samples] > 1, performs multiple HTTP requests and selects the
  /// measurement with the lowest round-trip delay.
  @override
  Future<NtpResponse> query({int samples = 1}) async {
    assert(samples >= 1, 'samples must be at least 1.');
    final uri = apiUrl != null ? Uri.parse(apiUrl!) : _defaultUri;

    ({int offsetMicros, int rttMicros})? bestSample;
    Object? lastError;
    StackTrace? lastStack;

    for (var i = 0; i < samples; i++) {
      try {
        final sample = await _querySingleWebSample(uri);
        if (bestSample == null || sample.rttMicros < bestSample.rttMicros) {
          bestSample = sample;
        }
      } catch (e, s) {
        lastError = e;
        lastStack = s;
        if (samples == 1) rethrow;
      }
    }

    if (bestSample == null) {
      Error.throwWithStackTrace(
        lastError ?? Exception('All $samples web time samples failed'),
        lastStack ?? StackTrace.current,
      );
    }

    final correctedTime = DateTime.now()
        .toUtc()
        .add(Duration(microseconds: bestSample.offsetMicros));

    return NtpResponse(
      dateTime: isUtc ? correctedTime : correctedTime.toLocal(),
      offset: Duration(microseconds: bestSample.offsetMicros),
      roundTripDelay: Duration(microseconds: bestSample.rttMicros),
      server: uri.toString(),
      stratum: 1,
      leapIndicator: 0,
      referenceId: 'WEB',
    );
  }

  Future<({int offsetMicros, int rttMicros})> _querySingleWebSample(
    Uri uri,
  ) async {
    final rttWatch = Stopwatch()..start();

    final response = await http.get(uri).timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        throw TimeoutException('Timeout fetching time from API');
      },
    );

    final latencyMicros = rttWatch.elapsedMicroseconds;
    final arrivalUtc = DateTime.now().toUtc();

    if (response.statusCode != 200) {
      throw Exception(
        'Error ${response.statusCode}: failed to fetch time from API',
      );
    }

    try {
      final DateTime serverDate;
      if (parseResponse != null) {
        serverDate = parseResponse!(response);
      } else {
        serverDate = parseWebDateString(
          response.body,
          dateHeader: response.headers['date'],
        );
      }

      final compensatedServerUtc =
          serverDate.toUtc().add(Duration(microseconds: latencyMicros ~/ 2));
      final offsetMicros =
          compensatedServerUtc.difference(arrivalUtc).inMicroseconds;

      return (offsetMicros: offsetMicros, rttMicros: latencyMicros);
    } catch (e) {
      throw Exception('Error parsing time from API: $e');
    }
  }

  /// Parses an HTTP-date (RFC 1123), Cloudflare trace (`ts=...`), or ISO-8601
  /// string into a UTC [DateTime] without external dependencies.
  static DateTime parseWebDateString(String body, {String? dateHeader}) {
    final trimmed = body.trim().replaceAll('"', '');

    // 1. Try RFC 1123 HTTP-date (e.g. "Wed, 14 Oct 2026 08:00:00 GMT")
    final rfcMatch = _rfc1123RegExp.firstMatch(trimmed);
    if (rfcMatch != null) {
      final day = int.parse(rfcMatch.group(1)!);
      final month = _months[rfcMatch.group(2)!];
      if (month != null) {
        final year = int.parse(rfcMatch.group(3)!);
        final hour = int.parse(rfcMatch.group(4)!);
        final minute = int.parse(rfcMatch.group(5)!);
        final second = int.parse(rfcMatch.group(6)!);
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    }

    // 2. Try Cloudflare trace format (e.g. "ts=1760428800.123")
    final cfMatch = _cloudflareTraceRegExp.firstMatch(trimmed);
    if (cfMatch != null) {
      final seconds = int.parse(cfMatch.group(1)!);
      final fracStr = (cfMatch.group(2) ?? '').padRight(6, '0').substring(0, 6);
      final micros = int.parse(fracStr);
      return DateTime.fromMicrosecondsSinceEpoch(
        seconds * 1000000 + micros,
        isUtc: true,
      );
    }

    // 3. Try ISO-8601
    final isoParsed = DateTime.tryParse(trimmed);
    if (isoParsed != null) {
      return isoParsed.toUtc();
    }

    // 4. Fallback to HTTP Date header if present
    if (dateHeader != null && dateHeader.isNotEmpty) {
      final headerMatch = _rfc1123RegExp.firstMatch(dateHeader.trim());
      if (headerMatch != null) {
        final day = int.parse(headerMatch.group(1)!);
        final month = _months[headerMatch.group(2)!];
        if (month != null) {
          final year = int.parse(headerMatch.group(3)!);
          final hour = int.parse(headerMatch.group(4)!);
          final minute = int.parse(headerMatch.group(5)!);
          final second = int.parse(headerMatch.group(6)!);
          return DateTime.utc(year, month, day, hour, minute, second);
        }
      }
    }

    throw FormatException('Unsupported time format: "$body"');
  }
}
