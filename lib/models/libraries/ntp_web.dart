import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'ntp_base.dart';

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
  });

  /// The base URL of the time API endpoint.
  ///
  /// Defaults to Postman Echo's `/time/now` service, which returns
  /// the current GMT time in its response body as a string.
  static const String _api = 'https://postman-echo.com/time/now';

  /// Fetches the current server time from the configured HTTP API.
  ///
  /// Sends an HTTP GET request to the API endpoint defined by [_api].
  /// If the response status code is not `200`, throws an [Exception]
  /// describing the HTTP error.
  ///
  /// The method expects the body to contain a date string in the format:
  /// `"EEE, dd MMM yyyy HH:mm:ss 'GMT'"`. This string is parsed into a UTC
  /// [DateTime] and returned.
  ///
  /// Throws an [Exception] if the HTTP request fails, times out, or the
  /// date parsing does not succeed.
  @override
  Future<DateTime> now() async {
    final uri = Uri.parse(apiUrl ?? _api);
    final startTime = DateTime.now();

    final response = await http.get(uri).timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        throw Exception('Timeout fetching time from API');
      },
    );

    final endTime = DateTime.now();

    if (response.statusCode != 200) {
      throw Exception(
        'Error ${response.statusCode}: failed to fetch time from API',
      );
    }

    try {
      DateTime serverDate;
      if (parseResponse != null) {
        serverDate = parseResponse!(response);
      } else {
        final String stringDate = response.body;
        final DateFormat format =
            DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
        serverDate = format.parseUTC(stringDate);
      }

      final latency = endTime.difference(startTime);
      return serverDate.add(latency ~/ 2);
    } catch (e) {
      throw Exception('Error parsing time from API: $e');
    }
  }
}
