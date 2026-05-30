import 'dart:async';
import 'dart:convert';
import 'package:ntp_dart/ntp_dart.dart';

Future<void> main() async {
  _printHeader('⏱️  NTP DART EXAMPLE');
  print('Local System Time: ${DateTime.now()}');
  print('Local UTC Time:    ${DateTime.now().toUtc()}');

  await _runDirectNtpFetch();
  await _runAccurateTimeDemo();
  await _runFlexibleConfigurationDemo();
  await _runCustomWebApi();
  await _runTimezoneCheck();

  _printHeader('🏁  Example Completed');
}

/// 1. Direct NTP Fetch
Future<void> _runDirectNtpFetch() async {
  _printSection('1. Direct NTP Fetch');
  print('Fetching time from default NTP server...');
  try {
    final now = await const NtpClient().now();
    print('✅ NTP Time (Default): $now');
  } catch (e) {
    print('❌ NTP Fetch Error: $e');
  }
}

/// 2. AccurateTime (Cached & Auto-Sync)
Future<void> _runAccurateTimeDemo() async {
  _printSection('2. AccurateTime (Cached & Auto-Sync)');
  print('Initializing AccurateTime with 5s sync interval...');

  // Set a short interval to demonstrate re-syncing behavior
  AccurateTime.setSyncInterval(const Duration(seconds: 5));

  // First call fetches from network and caches the computed offset
  final accurateInitial = await AccurateTime.now();
  print('✅ AccurateTime (Network First Sync): $accurateInitial');

  // Verify synchronous access (uses cached offset immediately)
  print('✅ AccurateTime (Cached Sync):        ${AccurateTime.nowSync()}');

  // Inspect the cached offset and last sync timestamp
  print('📊 Cached Offset:                    ${AccurateTime.cachedOffset}');
  print('⏰ Last Sync Time:                   ${AccurateTime.lastSyncTime}');

  print('\nWaiting for 6 seconds to trigger auto-resync...');
  await Future<void>.delayed(const Duration(seconds: 6));

  // Next call will trigger a background sync because cache has expired
  final accurateResync = await AccurateTime.now();
  print('✅ AccurateTime (Stale cache read):  $accurateResync');
}

/// 3. Flexible Configurations (NtpServer, forceRefresh, allowFallback)
Future<void> _runFlexibleConfigurationDemo() async {
  _printSection('3. Flexible Configurations & Fallbacks');

  // Querying using the Cloudflare NTP Server from the NtpServer enum
  print('Querying Cloudflare NTP server...');
  try {
    final cloudflareTime = await AccurateTime.now(
      server: NtpServer.cloudflare,
      forceRefresh: true, // Bypasses the cache entirely
    );
    print('✅ Cloudflare Time (Forced Refresh): $cloudflareTime');
  } catch (e) {
    print('❌ Cloudflare Fetch Error: $e');
  }

  // Graceful Fallback Handling Demo
  print('\nSimulating network failure with a broken NTP server url...');
  try {
    // Calling with allowFallback: true (default) returns local device time instead of crashing
    final fallbackTime = await AccurateTime.now(
      customServer: 'broken.ntp.server.url',
      forceRefresh: true,
      allowFallback: true, // Will fallback to local system clock on error
    );
    print('✅ Fallback Time (Recovered gracefully): $fallbackTime');

    // Calling with allowFallback: false propagates the exception
    print('Querying again with allowFallback: false (expects error)...');
    await AccurateTime.now(
      customServer: 'broken.ntp.server.url',
      forceRefresh: true,
      allowFallback: false, // Will throw the exception
    );
  } catch (e) {
    print('✅ Expected Error caught successfully: $e');
  }

  // Clear cache demo
  print('\nClearing the cached offset...');
  AccurateTime.clearCache();
  print('📊 Cached Offset after clear:        ${AccurateTime.cachedOffset}');
}

/// 4. Custom Web API (Web Only Demo)
Future<void> _runCustomWebApi() async {
  _printSection('4. Custom Web API (Web-only features)');
  print('Fetching time from WorldTimeAPI using custom parser...');
  try {
    final customTime = await NtpClient(
      apiUrl: 'https://worldtimeapi.org/api/timezone/Etc/UTC',
      parseResponse: (response) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return DateTime.parse(json['utc_datetime'] as String);
      },
      timeout: 10,
    ).now();
    print('✅ Custom API Time:   $customTime');
  } catch (e) {
    print('❌ Custom API Error:  $e');
  }
}

/// 5. Timezone Support
Future<void> _runTimezoneCheck() async {
  _printSection('5. Timezone Support');
  print('Checking UTC vs Local time retrieval...');
  try {
    final utcTime = await const NtpClient(isUtc: true).now();
    print('✅ NTP Time (UTC):   $utcTime\t(isUtc: ${utcTime.isUtc})');

    final localTime = await const NtpClient().now();
    print('✅ NTP Time (Local): $localTime\t(isUtc: ${localTime.isUtc})');

    print('\nChecking AccurateTime UTC vs Local...');
    final accurateUtc = await AccurateTime.now(isUtc: true);
    print(
        '✅ AccurateTime (UTC):   $accurateUtc\t(isUtc: ${accurateUtc.isUtc})');

    final accurateLocal = await AccurateTime.now();
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
