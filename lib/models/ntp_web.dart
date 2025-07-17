import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class NtpClient {
  static const String _api = 'https://postman-echo.com/time/now';

  static Future<DateTime> fetchServerTime() async {
    final uri = Uri.parse('$_api');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'Error ${response.statusCode}: wrong catch time from api',
      );
    }

    try {
      final stringDate = response.body;
      final format = DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
      return format.parseUTC(stringDate);
    } catch (e) {
      throw Exception('Error parsing time from api');
    }
  }
}
