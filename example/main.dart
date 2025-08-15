import 'package:ntp_dart/ntp_dart.dart';

void main() async {
  // Optional: reduce the sync interval for demonstration purposes
  AccurateTime.setSyncInterval(Duration(seconds: 5));

  print('LOCAL SYSTEM TIME: ${DateTime.now().toUtc()}');
  print('INITIAL SYNC TIME: ${AccurateTime.nowSync()}');
  print('----------------------------------------------------');

  // Fetch the current UTC time directly from the NTP server.
  final ntpNow = await NtpClient().now();
  print('NTP CLIENT TIME:   $ntpNow');
  print('----------------------------------------------------');

  // Demonstrate cached AccurateTime over multiple calls
  for (int i = 1; i <= 3; i++) {
    final accurateNow = await AccurateTime.now();
    print('ACCURATE TIME [$i]: $accurateNow');
    await Future.delayed(Duration(seconds: 1));
  }

  print('----------------------------------------------------');
  print('Waiting to exceed sync interval...');
  await Future.delayed(Duration(seconds: 6));

  // After sync interval, AccurateTime will re-sync NTP
  final accurateResync = await AccurateTime.now();
  print('ACCURATE TIME (resynced): $accurateResync');
}
