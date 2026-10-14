import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ntp_dart/models/libraries/ntp_base.dart';

/// A web-based implementation of an NTP (Network Time Protocol) client.
///
/// This implementation retrieves the current server time via an HTTP API
/// rather than using a raw UDP socket (which is not available in web
/// environments).
///
/// By default, it queries the Postman Echo `/time/now` endpoint, which
/// returns the current GMT time as a string (e.g. `"Thu, 17 Jul 2025 12:34:56 GMT"`).
/// The response is then parsed into a UTC [DateTime] instance.
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

  /// The base URL of the time API endpoint.
  ///
  /// Defaults to Postman Echo's `/time/now` service, which returns
  /// the current GMT time in its response body as a string.
  static const String _api = 'https://postman-echo.com/time/now';

  /// Pre-parsed default URI to avoid repeated parsing on every call.
  static final Uri _defaultUri = Uri.parse(_api);

  /// Pre-compiled HTTP-date formatter to avoid pattern parsing on every call.
  static final DateFormat _httpDateFormat =
      DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');

  /// Fetches the current server time from the configured HTTP API.
  ///
  /// Sends an HTTP GET request to the API endpoint defined by [_api] (or [apiUrl]).
  /// If the response status code is not `200`, throws an [Exception]
  /// describing the HTTP error.
  ///
  /// By default, expects the body to contain a date string in the format:
  /// `"EEE, dd MMM yyyy HH:mm:ss 'GMT'"`.
  ///
  /// Throws a [TimeoutException] if the HTTP request times out, or an
  /// [Exception] if the request fails or date parsing does not succeed.
  @override
  Future<DateTime> now() async {
    final uri = apiUrl != null ? Uri.parse(apiUrl!) : _defaultUri;
    final rttWatch = Stopwatch()..start();

    final response = await http.get(uri).timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        throw TimeoutException('Timeout fetching time from API');
      },
    );

    final latencyMicros = rttWatch.elapsedMicroseconds;

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
        serverDate = _httpDateFormat.parse(response.body, true);
      }

      final correctedTime =
          serverDate.toUtc().add(Duration(microseconds: latencyMicros ~/ 2));

      return isUtc ? correctedTime : correctedTime.toLocal();
    } catch (e) {
      throw Exception('Error parsing time from API: $e');
    }
  }
}
