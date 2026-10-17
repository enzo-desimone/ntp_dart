import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ntp_dart/models/libraries/ntp_web.dart' as web;
import 'package:ntp_dart/ntp_dart.dart';
import 'package:test/test.dart';

Uint8List createMockNtpResponse({
  required Uint8List requestPacket,
  int stratum = 1,
  int leapIndicator = 0,
  int mode = 4,
  String referenceId = 'LOCL',
  DateTime? receiveTime,
  DateTime? transmitTime,
  bool spoofOrigin = false,
}) {
  final response = Uint8List(48);
  response[0] = ((leapIndicator & 0x03) << 6) | (0x03 << 3) | (mode & 0x07);
  response[1] = stratum & 0xFF;
  response[2] = 4;
  response[3] = 0xEC;

  final refBytes = ascii.encode(referenceId.padRight(4).substring(0, 4));
  response.setRange(12, 16, refBytes);

  final byteData = ByteData.view(response.buffer);

  for (var i = 0; i < 8; i++) {
    response[24 + i] =
        spoofOrigin ? (requestPacket[40 + i] ^ 0xFF) : requestPacket[40 + i];
  }

  final t2 = receiveTime ?? DateTime.now().toUtc();
  NtpClient.writeNtpTimestamp(byteData, 32, t2);

  final t3 = transmitTime ?? DateTime.now().toUtc();
  NtpClient.writeNtpTimestamp(byteData, 40, t3);

  return response;
}

class FakeNtpClient extends NtpBase implements NtpClient {
  FakeNtpClient({required this.nowMock, super.server = 'fake.server'})
      : super(isUtc: true);
  final Future<DateTime> Function() nowMock;

  @override
  Future<DateTime> now() => nowMock();
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

  group('AccurateTime Offline Handling & Edge Cases', () {
    setUp(() {
      AccurateTime.clearCache();
      AccurateTime.setRetryCooldown(const Duration(seconds: 15));
    });

    tearDown(() {
      AccurateTime.ntpClientFactory = null;
      AccurateTime.clearCache();
    });

    test(
        'failure leaves lastSyncTime null and respects retry cooldown on subsequent call',
        () async {
      var attempts = 0;
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            attempts++;
            throw Exception('Network unreachable');
          },
        );
      };

      // First call fails, returns fallback local time
      final time1 = await AccurateTime.now();
      expect(time1, isNotNull);
      expect(attempts, 1);
      expect(AccurateTime.cachedOffset, Duration.zero);
      expect(AccurateTime.lastSyncTime, isNull);
      expect(AccurateTime.lastFailedAttempt, isNotNull);

      // Immediate second call should be suppressed by cooldown
      final time2 = await AccurateTime.now();
      expect(time2, isNotNull);
      expect(attempts, 1); // Not called again!

      // Once cooldown is set to 0, it retries and succeeds if network is restored
      AccurateTime.setRetryCooldown(Duration.zero);
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            attempts++;
            return DateTime.now().toUtc().add(const Duration(seconds: 4));
          },
        );
      };

      await AccurateTime.now();
      expect(attempts, 2);
      expect(AccurateTime.cachedOffset!.inSeconds, closeTo(4, 1));
      expect(AccurateTime.lastSyncTime, isNotNull);
      expect(AccurateTime.lastFailedAttempt, isNull);
    });

    test('cooldown prevents repeated background sync spam in nowSync()',
        () async {
      var attempts = 0;
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async {
            attempts++;
            throw TimeoutException('Timed out');
          },
        );
      };

      // Trigger first sync via nowSync
      AccurateTime.nowSync();
      // Allow async task to fail
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 1);

      // Subsequent 5 calls to nowSync should NOT trigger new syncs because cooldown is active
      for (var i = 0; i < 5; i++) {
        AccurateTime.nowSync();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 1);
    });

    test('clearCache() invalidates in-flight sync and prevents stale overwrite',
        () async {
      final completer = Completer<DateTime>();
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () => completer.future,
        );
      };

      // Start sync
      final future = AccurateTime.now();

      // Clear cache while sync is still running
      AccurateTime.clearCache();
      expect(AccurateTime.cachedOffset, isNull);

      // Complete in-flight sync with a 100s offset
      completer.complete(
        DateTime.now().toUtc().add(const Duration(seconds: 100)),
      );
      await future;

      // The in-flight sync should NOT have resurrected the cache!
      expect(AccurateTime.cachedOffset, isNull);
      expect(AccurateTime.lastSyncTime, isNull);
    });
  });

  group('NtpClient IO Protocol & RFC 5905 Validation', () {
    test('buildNtpPacket constructs valid 48-byte packet with client mode 3',
        () {
      final time = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final packet = NtpClient.buildNtpPacket(time);

      expect(packet.length, 48);
      // Mode 3 (Client), Version 3, LI 0 => 0x1B
      expect(packet[0], 0x1B);
    });

    test('parseNtpTimestamps parses Era 0 (1970 - 2036) correctly', () {
      final packet = Uint8List(48);
      final byteData = ByteData.view(packet.buffer);

      // Set Transmit timestamp (bytes 40-47) to 2026-01-01 00:00:00 UTC
      // 2026-01-01 is 1767225600 Unix seconds.
      // NTP seconds = 1767225600 + 2208988800 = 3976214400
      const ntpSeconds = 1767225600 + 2208988800;
      byteData.setUint32(40, ntpSeconds);
      byteData.setUint32(44, 0); // 0 fractional

      final timestamps = NtpClient.parseNtpTimestamps(packet);
      expect(timestamps.transmitTimestamp, DateTime.utc(2026, 1, 1));
    });

    test('parseNtpTimestamps parses Era 1 (Year 2036+) rollover per RFC 4330',
        () {
      final packet = Uint8List(48);
      final byteData = ByteData.view(packet.buffer);

      // In Era 1, ntpSeconds < 2208988800.
      // E.g., ntpSeconds = 1000 => Year 2036
      byteData.setUint32(40, 1000);
      byteData.setUint32(44, 0);

      final timestamps = NtpClient.parseNtpTimestamps(packet);
      expect(timestamps.transmitTimestamp.year, 2036);
      expect(timestamps.transmitTimestamp.isUtc, isTrue);
    });

    test('matchesOriginTimestamp compares bytes 24-31 with bytes 40-47', () {
      final req = Uint8List(48);
      final res = Uint8List(48);

      for (var i = 0; i < 8; i++) {
        req[40 + i] = i + 10;
        res[24 + i] = i + 10;
      }

      expect(NtpClient.matchesOriginTimestamp(res, req), isTrue);

      res[24] = 99; // Corrupt first byte
      expect(NtpClient.matchesOriginTimestamp(res, req), isFalse);
    });

    test('local UDP loopback exchange calculates accurate time and offset',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final res = createMockNtpResponse(requestPacket: datagram.data);
            server.send(res, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final result = await client.now();
      expect(result.isUtc, isTrue);
      expect(result.difference(DateTime.now()).inSeconds, closeTo(0, 2));
    });

    test('local UDP loopback handles Kiss-o-Death (Stratum 0) properly',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final res = createMockNtpResponse(
              requestPacket: datagram.data,
              stratum: 0,
              referenceId: 'RATE',
            );
            server.send(res, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
      );

      expect(
        () => client.now(),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains("Kiss-o'-Death") &&
                e.toString().contains('RATE'),
          ),
        ),
      );
    });

    test('local UDP loopback detects unsynchronized clock (Leap Indicator 3)',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final res = createMockNtpResponse(
              requestPacket: datagram.data,
              leapIndicator: 3,
            );
            server.send(res, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
      );

      expect(
        () => client.now(),
        throwsA(
          predicate(
            (e) => e.toString().contains('leap indicator: 3'),
          ),
        ),
      );
    });

    test(
        'client discards spoofed origin packet and accepts subsequent valid packet',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            // First send spoofed packet
            final spoofed = createMockNtpResponse(
              requestPacket: datagram.data,
              spoofOrigin: true,
            );
            server.send(spoofed, datagram.address, datagram.port);

            // Then send valid packet after 10ms
            Future.delayed(const Duration(milliseconds: 10), () {
              final valid = createMockNtpResponse(requestPacket: datagram.data);
              server.send(valid, datagram.address, datagram.port);
            });
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final result = await client.now();
      expect(result.difference(DateTime.now()).inSeconds, closeTo(0, 2));
    });

    test('multiple responses do not throw Future already completed', () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final valid = createMockNtpResponse(requestPacket: datagram.data);
            // Send multiple duplicates
            server.send(valid, datagram.address, datagram.port);
            server.send(valid, datagram.address, datagram.port);
            server.send(valid, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
      );

      final result = await client.now();
      expect(result, isNotNull);
      // Allow event loop to process duplicate datagrams
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test(
        'writeNtpTimestamp and parseNtpTimestamps preserve exact microsecond precision via integer math',
        () {
      final packet = Uint8List(48);
      final byteData = ByteData.view(packet.buffer);

      for (final micro in [0, 1, 7, 123456, 500000, 876543, 999999]) {
        final expected = DateTime.utc(2026, 10, 14, 12, 30, 45, 0, micro);
        NtpClient.writeNtpTimestamp(byteData, 40, expected);
        final parsed = NtpClient.parseNtpTimestamps(packet).transmitTimestamp;
        expect(
          parsed.microsecondsSinceEpoch,
          expected.microsecondsSinceEpoch,
          reason: 'Failed exact round-trip for microsecond=$micro',
        );
      }
    });

    test(
        'drains socket buffer in single burst when truncated and spoofed packets precede valid packet',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            // 1. Send truncated 10-byte packet immediately
            server.send(Uint8List(10), datagram.address, datagram.port);
            // 2. Send spoofed packet immediately
            final spoofed = createMockNtpResponse(
              requestPacket: datagram.data,
              spoofOrigin: true,
            );
            server.send(spoofed, datagram.address, datagram.port);
            // 3. Send valid packet immediately (and retry if OS non-blocking send buffer was busy)
            final valid = createMockNtpResponse(requestPacket: datagram.data);
            final sent = server.send(valid, datagram.address, datagram.port);
            if (sent == 0) {
              Future<void>.delayed(const Duration(milliseconds: 5), () {
                server.send(valid, datagram.address, datagram.port);
              });
            }
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final result = await client.now();
      expect(result.difference(DateTime.now()).inSeconds, closeTo(0, 2));
    });

    test('gracefully handles SNTP server that omits receiveTimestamp (T2 == 0)',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final res = createMockNtpResponse(requestPacket: datagram.data);
            // Zero out Receive Timestamp (bytes 32..39)
            for (var i = 32; i < 40; i++) {
              res[i] = 0;
            }
            server.send(res, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final result = await client.now();
      expect(result.difference(DateTime.now()).inSeconds, closeTo(0, 2));
    });

    test('NtpBase constructor asserts on invalid port or timeout', () {
      expect(() => NtpClient(port: 0), throwsA(isA<AssertionError>()));
      expect(() => NtpClient(port: 70000), throwsA(isA<AssertionError>()));
      expect(() => NtpClient(timeout: 0), throwsA(isA<AssertionError>()));
      expect(() => NtpClient(timeout: -1), throwsA(isA<AssertionError>()));
    });
  });

  group('NtpClient Web Platform Edge Cases', () {
    test('now() with isUtc: false returns local time (isUtc == false)',
        () async {
      await http.runWithClient(() async {
        final client = web.NtpClient(
          apiUrl: 'https://mock.api/time',
          isUtc: false,
          parseResponse: (_) => DateTime.utc(2026, 6, 1, 12, 0, 0),
        );
        final time = await client.now();
        expect(time.isUtc, isFalse);
      }, () => MockClient((_) async => http.Response('ok', 200)));
    });

    test('now() with isUtc: true returns UTC time (isUtc == true)', () async {
      await http.runWithClient(() async {
        final client = web.NtpClient(
          apiUrl: 'https://mock.api/time',
          isUtc: true,
          parseResponse: (_) => DateTime.utc(2026, 6, 1, 12, 0, 0),
        );
        final time = await client.now();
        expect(time.isUtc, isTrue);
      }, () => MockClient((_) async => http.Response('ok', 200)));
    });

    test('now() parses default HTTP GMT date format accurately', () async {
      await http.runWithClient(
        () async {
          const client = web.NtpClient(isUtc: true);
          final time = await client.now();
          expect(time.isUtc, isTrue);
          expect(time.year, 2026);
          expect(time.month, 10);
          expect(time.day, 14);
        },
        () => MockClient(
          (_) async => http.Response('Wed, 14 Oct 2026 08:00:00 GMT', 200),
        ),
      );
    });

    test('now() throws TimeoutException on HTTP timeout', () async {
      await http.runWithClient(
        () async {
          const client = web.NtpClient(timeout: 1);
          expect(
            () => client.now(),
            throwsA(isA<TimeoutException>()),
          );
        },
        () => MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response('Wed, 14 Oct 2026 08:00:00 GMT', 200);
        }),
      );
    });

    test('now() throws exception on HTTP error status code', () async {
      await http.runWithClient(() async {
        final client = web.NtpClient(
          apiUrl: 'https://mock.api/time',
          parseResponse: (_) => DateTime.now(),
        );
        expect(
          () => client.now(),
          throwsA(
            predicate<Object>((e) => e.toString().contains('Error 500')),
          ),
        );
      }, () => MockClient((_) async => http.Response('Internal Error', 500)));
    });

    test(
        'parseWebDateString supports Cloudflare trace, ISO-8601, and Date header',
        () {
      // Cloudflare trace format with sub-second precision
      final cf = web.NtpClient.parseWebDateString(
        'fl=29f12\nts=1760428800.125\nip=1.1.1.1',
      );
      expect(cf, DateTime.utc(2025, 10, 14, 8, 0, 0, 125));

      // ISO-8601 format
      final iso = web.NtpClient.parseWebDateString('2026-10-14T08:00:00.500Z');
      expect(iso, DateTime.utc(2026, 10, 14, 8, 0, 0, 500));

      // HTTP Date header fallback when body is empty or non-date
      final headerTime = web.NtpClient.parseWebDateString(
        'ok',
        dateHeader: 'Wed, 14 Oct 2026 08:00:00 GMT',
      );
      expect(headerTime, DateTime.utc(2026, 10, 14, 8, 0, 0));
    });
  });

  group('NtpResponse Telemetry, Multi-Sample & Advanced AccurateTime', () {
    setUp(() {
      AccurateTime.clearCache();
      AccurateTime.setRetryCooldown(const Duration(seconds: 15));
    });

    tearDown(() {
      AccurateTime.ntpClientFactory = null;
      AccurateTime.clearCache();
    });

    test('NtpClient.query() returns full RFC 5905 NtpResponse telemetry',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            final res = createMockNtpResponse(
              requestPacket: datagram.data,
              stratum: 1,
              leapIndicator: 0,
              referenceId: 'GOOG',
            );
            server.send(res, datagram.address, datagram.port);
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final response = await client.query();
      expect(response.dateTime.isUtc, isTrue);
      expect(response.stratum, 1);
      expect(response.leapIndicator, 0);
      expect(response.referenceId, 'GOOG');
      expect(response.server, '127.0.0.1');
      expect(response.roundTripDelay.inMicroseconds, greaterThanOrEqualTo(0));
      expect(response.toString(), contains('stratum: 1'));
    });

    test(
        'NtpClient.query(samples: 3) selects lowest RTT sample and tolerates partial packet loss',
        () async {
      late RawDatagramSocket server;
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;
      var packetCount = 0;

      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = server.receive();
          if (datagram != null) {
            packetCount++;
            final delayMs = packetCount == 1 ? 40 : 2;
            Future.delayed(Duration(milliseconds: delayMs), () {
              final res = createMockNtpResponse(
                requestPacket: datagram.data,
                stratum: 2,
                referenceId: '\x08\x08\x08\x08',
              );
              server.send(res, datagram.address, datagram.port);
            });
          }
        }
      });

      addTearDown(() => server.close());

      final client = NtpClient(
        server: '127.0.0.1',
        port: serverPort,
        timeout: 2,
        isUtc: true,
      );

      final response = await client.query(samples: 3);
      expect(packetCount, 3);
      expect(response.stratum, 2);
      expect(response.referenceId, '8.8.8.8');
      expect(response.roundTripDelay.inMilliseconds, lessThan(35));
    });

    test('AccurateTime.now() falls back to fallbackServers when primary fails',
        () async {
      final queriedServers = <String>[];
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          server: server,
          nowMock: () async {
            queriedServers.add(server);
            if (server == NtpServer.google.url) {
              throw TimeoutException('Primary server timed out');
            }
            return DateTime.now().toUtc().add(const Duration(seconds: 7));
          },
        );
      };

      final time = await AccurateTime.now(
        server: NtpServer.google,
        fallbackServers: [NtpServer.cloudflare, NtpServer.apple],
        allowFallback: false,
      );

      expect(queriedServers, [NtpServer.google.url, NtpServer.cloudflare.url]);
      expect(AccurateTime.cachedOffset!.inSeconds, closeTo(7, 1));
      expect(AccurateTime.lastSyncDetails?.server, NtpServer.cloudflare.url);
      expect(time, isNotNull);
    });

    test('AccurateTime.query() returns cached NtpResponse telemetry', () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          server: server,
          nowMock: () async =>
              DateTime.now().toUtc().add(const Duration(seconds: 3)),
        );
      };

      final response = await AccurateTime.query(isUtc: true);
      expect(response.offset.inSeconds, closeTo(3, 1));
      expect(response.dateTime.isUtc, isTrue);
      expect(AccurateTime.lastSyncDetails, isNotNull);
    });

    test('AccurateTime.restoreCache() hydrates offset for offline startup', () {
      AccurateTime.restoreCache(offset: const Duration(seconds: 42));
      expect(AccurateTime.cachedOffset, const Duration(seconds: 42));
      expect(AccurateTime.lastSyncDetails?.referenceId, 'CACH');
      expect(AccurateTime.isTampered, isFalse);

      final syncNow = AccurateTime.nowSync(isUtc: true);
      expect(
        syncNow.difference(DateTime.now().toUtc()).inSeconds,
        closeTo(42, 1),
      );
    });

    test(
        'AccurateTime.isTampered and onClockTampered detect manual clock jumps',
        () async {
      final tamperEvents = <Duration>[];
      final sub = AccurateTime.onClockTampered.listen(tamperEvents.add);
      addTearDown(sub.cancel);

      // Simulate a sync that happened 10 minutes ago on wall-clock,
      // while monotonic stopwatch just recorded now (10m clock jump!)
      AccurateTime.restoreCache(
        offset: const Duration(seconds: 1),
        syncTime: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      expect(AccurateTime.isTampered, isTrue);

      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async => DateTime.now().toUtc(),
        );
      };

      // Calling now() detects tamper, emits onClockTampered, and re-syncs
      await AccurateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tamperEvents, isNotEmpty);
      expect(AccurateTime.isTampered, isFalse);
    });

    test('AccurateTime.stream() emits accurate periodic ticks', () async {
      AccurateTime.ntpClientFactory = ({
        server = 'pool.ntp.org',
        port = 123,
        timeout = 5,
        isUtc = true,
      }) {
        return FakeNtpClient(
          nowMock: () async =>
              DateTime.now().toUtc().add(const Duration(seconds: 5)),
        );
      };

      final ticks = await AccurateTime.stream(
        interval: const Duration(milliseconds: 20),
        isUtc: true,
      ).take(3).toList();

      expect(ticks.length, 3);
      for (final tick in ticks) {
        expect(tick.isUtc, isTrue);
        expect(
            tick.difference(DateTime.now().toUtc()).inSeconds, closeTo(5, 1));
      }
    });
  });
}
