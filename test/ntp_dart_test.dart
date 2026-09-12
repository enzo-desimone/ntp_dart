import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ntp_dart/ntp_dart.dart';
import 'package:test/test.dart';

class FakeNtpClient implements NtpClient {
  FakeNtpClient({required this.nowMock});
  final Future<DateTime> Function() nowMock;

  @override
  Future<DateTime> now() => nowMock();

  @override
  String get server => 'fake.server';

  @override
  int get port => 123;

  @override
  int get timeout => 5;

  @override
  String? get apiUrl => null;

  @override
  DateTime Function(http.Response)? get parseResponse => null;

  @override
  bool get isUtc => true;
}

void main() {
  group('NtpServer Enum', () {
    test('contains expected curated public servers', () {
      expect(NtpServer.google.url, 'time.google.com');
      expect(NtpServer.cloudflare.url, 'time.cloudflare.com');
      expect(NtpServer.apple.url, 'time.apple.com');
      expect(NtpServer.microsoft.url, 'time.windows.com');
      expect(NtpServer.nist.url, 'time.nist.gov');
      expect(NtpServer.pool.url, 'pool.ntp.org');
    });
  });

  group('AccurateTime Caching and Logic', () {
    late List<DateTime> mockClientResponses;
    late int callCount;

    setUp(() {
      AccurateTime.clearCache();
      callCount = 0;
      mockClientResponses = [];

      // Inject fake client factory
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            callCount++;
            if (mockClientResponses.length >= callCount) {
              return mockClientResponses[callCount - 1];
            }
            return DateTime.now().toUtc();
          },
        );
      };
    });

    tearDown(() {
      AccurateTime.ntpClientFactory = null;
      AccurateTime.clearCache();
    });

    test('initial state has null cache', () {
      expect(AccurateTime.cachedOffset, isNull);
      expect(AccurateTime.lastSyncTime, isNull);
    });

    test('now() successfully fetches, calculates offset and caches it',
        () async {
      final nowLocal = DateTime.now();
      // Server is 5 seconds ahead
      final fakeServerTime = nowLocal.add(const Duration(seconds: 5)).toUtc();
      mockClientResponses = [fakeServerTime];

      final time = await AccurateTime.now(isUtc: true);

      expect(callCount, 1);
      expect(AccurateTime.cachedOffset, isNotNull);
      // Offset should be around +5 seconds
      expect(AccurateTime.cachedOffset!.inSeconds, closeTo(5, 1));
      expect(AccurateTime.lastSyncTime, isNotNull);

      // Returned time should be close to the fake server time
      expect(time.difference(fakeServerTime).inSeconds, closeTo(0, 1));
    });

    test('now() uses cached offset on subsequent calls within interval',
        () async {
      final nowLocal = DateTime.now();
      final fakeServerTime = nowLocal.add(const Duration(seconds: 5)).toUtc();
      mockClientResponses = [
        fakeServerTime,
        fakeServerTime.add(const Duration(minutes: 5)),
      ];

      final firstCall = await AccurateTime.now(isUtc: true);
      final secondCall = await AccurateTime.now(isUtc: true);

      expect(callCount, 1); // Only queried once!
      expect(firstCall.difference(secondCall).inSeconds, closeTo(0, 2));
    });

    test('now() forceRefresh bypasses cache', () async {
      final nowLocal = DateTime.now();
      final fakeServerTime1 = nowLocal.add(const Duration(seconds: 5)).toUtc();
      final fakeServerTime2 = nowLocal.add(const Duration(seconds: 15)).toUtc();
      mockClientResponses = [fakeServerTime1, fakeServerTime2];

      await AccurateTime.now(isUtc: true);
      await AccurateTime.now(isUtc: true, forceRefresh: true);

      expect(callCount, 2); // Bypassed cache!
      expect(AccurateTime.cachedOffset!.inSeconds, closeTo(15, 1));
    });

    test('now() allowFallback recovers gracefully on network error', () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            throw Exception('Failed to connect to NTP server');
          },
        );
      };

      // With fallback allowed (default)
      final time = await AccurateTime.now();
      expect(time, isNotNull);
      expect(
        AccurateTime.cachedOffset,
        Duration.zero,
      ); // stored zero fallback offset

      // With fallback disabled
      expect(
        () => AccurateTime.now(allowFallback: false, forceRefresh: true),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'nowSync() returns local time immediately on first call and triggers background sync',
        () async {
      final completer = Completer<void>();
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            callCount++;
            completer.complete();
            return DateTime.now().toUtc().add(const Duration(seconds: 10));
          },
        );
      };

      final time = AccurateTime.nowSync(isUtc: true);
      // First synchronous call returns immediately (local time)
      expect(time.difference(DateTime.now()).inSeconds, closeTo(0, 1));
      expect(AccurateTime.cachedOffset, isNull);

      // Wait for background sync to complete
      await completer.future;
      // Allow microtask queue to process the return value from mock and assignment
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);
      expect(AccurateTime.cachedOffset, isNotNull);
      expect(AccurateTime.cachedOffset!.inSeconds, closeTo(10, 1));
    });

    test(
        'nowSync() background sync failure does not produce unhandled async error',
        () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            throw TimeoutException('Timeout while contacting the NTP server');
          },
        );
      };

      expect(() => AccurateTime.nowSync(), returnsNormally);

      // Wait for background task to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(AccurateTime.cachedOffset, Duration.zero);
    });

    test(
        'nowSync() background sync DNS lookup failure does not produce unhandled async error',
        () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            throw Exception(
              "Unable to resolve NTP server address: SocketException: Failed host lookup: 'time.google.com' (OS Error: nodename nor servname provided, or not known, errno = 8)",
            );
          },
        );
      };

      expect(() => AccurateTime.nowSync(), returnsNormally);

      // Wait for background task to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(AccurateTime.cachedOffset, Duration.zero);
    });

    test('nowSync() deduplicates concurrent background sync requests',
        () async {
      final completer = Completer<DateTime>();
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            callCount++;
            return completer.future;
          },
        );
      };

      AccurateTime.nowSync();
      AccurateTime.nowSync();
      AccurateTime.nowSync();

      expect(callCount, 1);

      completer.complete(DateTime.now().toUtc());
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('now() deduplicates concurrent sync requests', () async {
      final completer = Completer<DateTime>();
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            callCount++;
            return completer.future;
          },
        );
      };

      final future1 = AccurateTime.now(isUtc: true);
      final future2 = AccurateTime.now(isUtc: true);

      expect(callCount, 1);

      final fakeServerTime =
          DateTime.now().toUtc().add(const Duration(seconds: 10));
      completer.complete(fakeServerTime);

      final res1 = await future1;
      final res2 = await future2;

      expect(callCount, 1);
      expect(res1.difference(fakeServerTime).inSeconds, closeTo(0, 1));
      expect(res2.difference(fakeServerTime).inSeconds, closeTo(0, 1));
    });

    test(
        'concurrent now(allowFallback: false) throws on error while nowSync is unhurt',
        () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            throw TimeoutException('Timeout while contacting the NTP server');
          },
        );
      };

      // nowSync triggers background sync
      AccurateTime.nowSync();

      // now(allowFallback: false) joins in-flight sync and propagates failure
      expect(
        () => AccurateTime.now(allowFallback: false),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('clearCache() empties cache values', () async {
      mockClientResponses = [DateTime.now().toUtc()];
      await AccurateTime.now();
      expect(AccurateTime.cachedOffset, isNotNull);

      AccurateTime.clearCache();
      expect(AccurateTime.cachedOffset, isNull);
      expect(AccurateTime.lastSyncTime, isNull);
    });

    test('nowToIsoString() returns correct ISO 8601 string', () async {
      mockClientResponses = [DateTime.parse('2026-05-30T12:00:00Z')];
      final iso = await AccurateTime.nowToIsoString();
      expect(iso, '2026-05-30T12:00:00.000Z');
    });

    test('setSyncInterval() modifies cache staleness check', () async {
      final nowLocal = DateTime.now();
      mockClientResponses = [
        nowLocal.toUtc(),
        nowLocal.toUtc().add(const Duration(seconds: 10)),
      ];

      // Initial query caches value
      await AccurateTime.now();
      expect(callCount, 1);

      // Shorten interval to 10 milliseconds
      AccurateTime.setSyncInterval(const Duration(milliseconds: 10));

      // Wait for it to become stale
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Query again - should refresh cache
      await AccurateTime.now();
      expect(callCount, 2);

      // Reset sync interval to default
      AccurateTime.setSyncInterval(const Duration(minutes: 60));
    });
  });

  group('NtpClient Web Custom Parsing', () {
    test('parseResponse custom callback parses response successfully', () {
      final mockResponse = http.Response(
        '{"utc_datetime": "2026-05-30T12:00:00Z"}',
        200,
      );
      final parsed = DateTime.parse('2026-05-30T12:00:00Z');

      final client = NtpClient(
        apiUrl: 'https://fake-url.com',
        parseResponse: (res) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          return DateTime.parse(json['utc_datetime'] as String);
        },
      );

      final result = client.parseResponse!(mockResponse);
      expect(result, parsed);
    });
  });
}
