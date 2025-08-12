import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// A simple NTP client that retrieves the current server time
/// from a remote HTTP API endpoint.
///
/// This client sends an HTTP GET request to the specified API URL,
/// parses the HTTP response body as a GMT-formatted date string,
/// and returns a [DateTime] object in UTC.
class NtpClient {
  /// The base URL of the time API endpoint.
  ///
  /// Defaults to Postman Echo's `/time/now` service, which returns
  /// the current GMT time in its response body as a string
  /// (e.g. "Thu, 17 Jul 2025 12:34:56 GMT").
  static const String _api = 'https://postman-echo.com/time/now';

  /// Fetches the current server time.
  ///
  /// Returns the time provided by the remote service as a [DateTime] in UTC.
  /// Sends an HTTP GET request to the configured API endpoint.
  /// If the response status code is not 200, throws an [Exception]
  /// indicating the HTTP error.
  ///
  /// Parses the response body using the format
  /// "EEE, dd MMM yyyy HH:mm:ss 'GMT'" and returns the
  /// resulting [DateTime] in UTC.
  ///
  /// Throws an [Exception] if parsing fails.
  Future<DateTime> now() async {
    final uri = Uri.parse(_api);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'Error ${response.statusCode}: failed to fetch time from API',
      );
    }

    try {
      final String stringDate = response.body;
      final DateFormat format =
          DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
      return format.parseUTC(stringDate);
    } catch (e) {
      throw Exception('Error parsing time from API: \$e');
    }
  }
}
