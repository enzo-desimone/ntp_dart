
import 'package:ntp_dart/ntp_dart.dart';

void main() async {
  // Fetch the current UTC time directly from the NTP client.
  final utcNow = await testNtpClient();
  print('----------------------------------------------------');
  print('NTP CLIENT UTC NOW: $utcNow');
  print('----------------------------------------------------');

  // Loop to demonstrate repeated calls to AccurateTime.
  // Each iteration fetches the "accurate" time (cached + drift) and prints it.
  for (final e in [1, 2, 3]) {
    final accurateNow = await testAccurateTime();
    print('ACCURATE TIME NOW: $accurateNow');
    print('----------------------------------------------------');
    await Future.delayed(Duration(seconds: 1)); // Wait 1 second between samples.
  }
}

// Fetches the current UTC time from the NTP client.
// Returns the DateTime received from the NTP server.
Future<DateTime> testNtpClient() async {
  final ntp = NtpClient();
  final utcNow = await ntp.now();
  return utcNow;
}

// Fetches the current "accurate" UTC time using the AccurateTime class.
// This uses a cached NTP time plus local clock drift adjustment.
Future<DateTime> testAccurateTime() async {
  return await AccurateTime.now();
}

