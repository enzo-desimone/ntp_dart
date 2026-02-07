import 'dart:async';
import 'dart:convert';
import 'package:ntp_dart/ntp_dart.dart';

/// Entry point of the example application.
///
/// This example demonstrates:
/// 1. Direct NTP fetch with latency compensation.
/// 2. Custom Web API usage (e.g., WorldTimeAPI).
/// 3. Cached time synchronization with `AccurateTime`.
/// 4. Handling sync intervals and background updates.
void main() async {
  print('================================================================');
  print('⏱️  NTP DART EXAMPLE');
  print('================================================================');
  print('Local System Time: ${DateTime.now().toUtc()} (UTC)');
  print('');

  // 1. Direct NTP Fetch
  // ----------------------------------------------------------------
  print('running direct NTP fetch...');
  try {
    // Uses pool.ntp.org (on mobile/desktop) or postman-echo (on web)
    // Applies latency compensation automatically.
    final now = await NtpClient().now();
    print('✅ NTP Time (Default): $now');
  } catch (e) {
    print('❌ NTP Fetch Error: $e');
  }
  print('');

  // 2. Custom Web API (Web Only Demo)
  // ----------------------------------------------------------------
  // Note: On mobile/desktop this will fall back to standard NTP via UDP,
  // ignoring apiUrl/parseResponse but keeping the same API surface.
  // On Web, it will use this specific endpoint and parser.
  print('running custom API fetch (Web only features)...');
  try {
    final customTime = await NtpClient(
      // Example: WorldTimeAPI which returns JSON
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
  print('');

  // 3. AccurateTime (Cached & Auto-Sync)
  // ----------------------------------------------------------------
  print('initializing AccurateTime...');

  // Set a short interval to demonstrate re-syncing behavior
  AccurateTime.setSyncInterval(Duration(seconds: 5));

  // First call fetches from network and caches result
  final accurateInitial = await AccurateTime.now();
  print('✅ AccurateTime (Network): $accurateInitial');

  // Verify synchronous access (uses cache)
  print('✅ AccurateTime (Cached):  ${AccurateTime.nowSync()}');

  print('\nWaiting for 6 seconds to trigger auto-resync...');
  await Future.delayed(Duration(seconds: 6));

  // Next call will trigger a background sync because cache is stale
  // but returns immediately with the best available time (or awaits if necessary)
  final accurateResync = await AccurateTime.now();
  print('✅ AccurateTime (Resync):  $accurateResync');

  print('\n================================================================');
  print('🏁  Example Completed');
  print('================================================================');
}
