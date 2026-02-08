import 'dart:async';
import 'dart:convert';
import 'package:ntp_dart/ntp_dart.dart';

/// Entry point of the example application.
Future<void> main() async {
  _printHeader('⏱️  NTP DART EXAMPLE');
  print('Local System Time: ${DateTime.now()}');
  print('Local UTC Time:    ${DateTime.now().toUtc()}');

  await _runDirectNtpFetch();
  await _runCustomWebApi();
  await _runAccurateTimeDemo();
  await _runTimezoneCheck();

  _printHeader('🏁  Example Completed');
}

/// 1. Direct NTP Fetch
Future<void> _runDirectNtpFetch() async {
  _printSection('1. Direct NTP Fetch');
  print('Fetching time from default NTP server...');
  try {
    final now = await NtpClient().now();
    print('✅ NTP Time (Default): $now');
  } catch (e) {
    print('❌ NTP Fetch Error: $e');
  }
}

/// 2. Custom Web API (Web Only Demo)
Future<void> _runCustomWebApi() async {
  _printSection('2. Custom Web API (Web-only features)');
  print('Fetching time from WorldTimeAPI...');
  try {
    final customTime = await NtpClient(
      apiUrl: 'https://worldtimeapi.org/api/timezone/Etc/UTC',
      parseResponse: (response) {
        final json = jsonDecode(response.body);
        return DateTime.parse(json['utc_datetime']);
      },
      timeout: 10,
    ).now();
    print('✅ Custom API Time:   $customTime');
  } catch (e) {
    print('❌ Custom API Error:  $e');
  }
}

/// 3. AccurateTime (Cached & Auto-Sync)
Future<void> _runAccurateTimeDemo() async {
  _printSection('3. AccurateTime (Cached & Auto-Sync)');
  print('Initializing AccurateTime with 5s sync interval...');

  // Set a short interval to demonstrate re-syncing behavior
  AccurateTime.setSyncInterval(const Duration(seconds: 5));

  // First call fetches from network and caches result
  final accurateInitial = await AccurateTime.now();
  print('✅ AccurateTime (Network): $accurateInitial');

  // Verify synchronous access (uses cache)
  print('✅ AccurateTime (Cached):  ${AccurateTime.nowSync()}');

  print('\nWaiting for 6 seconds to trigger auto-resync...');
  await Future.delayed(const Duration(seconds: 6));

  // Next call will trigger a background sync because cache is stale
  final accurateResync = await AccurateTime.now();
  print('✅ AccurateTime (Resync):  $accurateResync');
}

/// 4. Timezone Support
Future<void> _runTimezoneCheck() async {
  _printSection('4. Timezone Support');
  print('Checking UTC vs Local time retrieval...');
  try {
    final utcTime = await NtpClient(isUtc: true).now();
    print('✅ NTP Time (UTC):   $utcTime\t(isUtc: ${utcTime.isUtc})');

    final localTime = await NtpClient(isUtc: false).now();
    print('✅ NTP Time (Local): $localTime\t(isUtc: ${localTime.isUtc})');

    print('\nChecking AccurateTime UTC vs Local...');
    final accurateUtc = await AccurateTime.now(isUtc: true);
    print(
        '✅ AccurateTime (UTC):   $accurateUtc\t(isUtc: ${accurateUtc.isUtc})');

    final accurateLocal = await AccurateTime.now(isUtc: false);
    print(
        '✅ AccurateTime (Local): $accurateLocal\t(isUtc: ${accurateLocal.isUtc})');
  } catch (e) {
    print('❌ Timezone Check Error: $e');
  }
}

// --- Helpers ---

void _printHeader(String title) {
  print('\n================================================================');
  print(title);
  print('================================================================\n');
}

void _printSection(String title) {
  print('\n----------------------------------------------------------------');
  print(title);
  print('----------------------------------------------------------------');
}
