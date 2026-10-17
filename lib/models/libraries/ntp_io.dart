/// Socket-based UDP NTP client implementation for Mobile, Desktop, and Server.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ntp_dart/models/libraries/ntp_base.dart';
import 'package:ntp_dart/models/ntp_response.dart';

/// Internal raw measurement captured before socket cleanup.
typedef _RawNtpSample = ({
  int offsetMicros,
  int rttMicros,
  int stratum,
  int leapIndicator,
  String referenceId,
  int rootDelayMicros,
  int rootDispersionMicros,
});

/// A socket-based implementation of an NTP (Network Time Protocol) client.
///
/// This implementation communicates directly with an NTP server over UDP
/// to retrieve the current UTC time. It is intended for platforms where
/// raw sockets are available (e.g., mobile or desktop) and cannot be used
/// in browser environments.
///
/// By default, it queries the public NTP pool (`pool.ntp.org`) on port 123,
/// but the [server], [port], and [timeout] parameters can be customized
/// via the constructor.
class NtpClient extends NtpBase {
  /// Creates a new [NtpClient] instance with optional configuration parameters.
  ///
  /// - [server] specifies the NTP server hostname or IP address (default: `'pool.ntp.org'`)
  /// - [port] is the UDP port number for NTP communication (default: `123`)
  /// - [timeout] is the maximum duration in seconds to wait for a server response (default: `5`)
  const NtpClient({
    super.server,
    super.port,
    super.timeout,
    super.apiUrl,
    super.parseResponse,
    super.isUtc,
  });

  static final _random = Random.secure();

  static const int _ntpEpochOffset =
      2208988800; // Seconds between 1900 and 1970

  /// Retrieves the current [DateTime] from the configured NTP server.
  ///
  /// Opens a UDP socket, sends a standard 48-byte NTP request packet,
  /// waits for a response, and computes the clock offset using all four
  /// timestamps with full microsecond precision.
  ///
  /// Throws an [Exception] if the hostname cannot be resolved, if the
  /// server does not respond within [timeout] seconds, or if the packet
  /// is rejected by RFC 5905 validation.
  @override
  Future<DateTime> now() async {
    final response = await query();
    return response.dateTime;
  }

  /// Queries the configured NTP server and returns a full [NtpResponse]
  /// with RFC 5905 telemetry.
  ///
  /// When [samples] > 1, performs a multi-sample burst and selects the
  /// measurement with the lowest round-trip delay (RFC 5905 clock filter).
  @override
  Future<NtpResponse> query({int samples = 1}) async {
    assert(samples >= 1, 'samples must be at least 1.');
    final ntpAddress = await _resolveAddress();

    _RawNtpSample? bestSample;
    Object? lastError;
    StackTrace? lastStack;

    for (var i = 0; i < samples; i++) {
      try {
        final sample = await _querySingleSample(ntpAddress);
        if (bestSample == null || sample.rttMicros < bestSample.rttMicros) {
          bestSample = sample;
        }
      } catch (e, s) {
        lastError = e;
        lastStack = s;
        if (samples == 1) rethrow;
      }
    }

    if (bestSample == null) {
      Error.throwWithStackTrace(
        lastError ?? Exception('All $samples NTP samples failed'),
        lastStack ?? StackTrace.current,
      );
    }

    // Apply offset after all async cleanup has finished to prevent microtask/socket lag.
    final correctedTime =
        DateTime.now().add(Duration(microseconds: bestSample.offsetMicros));
    return NtpResponse(
      dateTime: isUtc ? correctedTime.toUtc() : correctedTime.toLocal(),
      offset: Duration(microseconds: bestSample.offsetMicros),
      roundTripDelay: Duration(microseconds: bestSample.rttMicros),
      server: server,
      stratum: bestSample.stratum,
      leapIndicator: bestSample.leapIndicator,
      referenceId: bestSample.referenceId,
      rootDelay: Duration(microseconds: bestSample.rootDelayMicros),
      rootDispersion: Duration(microseconds: bestSample.rootDispersionMicros),
    );
  }

  Future<_RawNtpSample> _querySingleSample(InternetAddress ntpAddress) async {
    final bindAddress = ntpAddress.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;

    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(bindAddress, 0);
    } catch (e) {
      throw Exception('Could not bind UDP socket: $e');
    }

    final completer = Completer<_RawNtpSample>();
    StreamSubscription<RawSocketEvent>? subscription;

    try {
      final rttWatch = Stopwatch()..start();
      final originateTime = DateTime.now().toUtc();
      final t1Micros = originateTime.microsecondsSinceEpoch;
      final packet = buildNtpPacket(originateTime);

      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;

          // Drain all available datagrams in the OS socket buffer.
          while (!completer.isCompleted) {
            final datagram = socket.receive();
            if (datagram == null) break;

            final elapsedMicros = rttWatch.elapsedMicroseconds;
            final data = datagram.data;
            if (data.length < 48) continue; // Discard truncated packet

            // RFC 5905: Validate Mode (4 = server, 5 = broadcast)
            final mode = data[0] & 0x07;
            if (mode != 4 && mode != 5) continue;

            // RFC 5905: Validate Origin Timestamp matches request Transmit Timestamp
            if (!matchesOriginTimestamp(data, packet)) {
              continue; // Discard spoofed or delayed response
            }

            // RFC 5905: Check Stratum (0 is Kiss-o'-Death, >15 is unsynchronized)
            final stratum = data[1];
            if (stratum == 0) {
              final code = _parseReferenceId(data, 0);
              completer.completeError(
                Exception(
                  "NTP server returned Kiss-o'-Death (KoD) code: $code",
                ),
              );
              return;
            }
            if (stratum > 15) {
              completer.completeError(
                Exception('NTP server is unsynchronized (stratum: $stratum)'),
              );
              return;
            }

            // RFC 5905: Check Leap Indicator (LI == 3 means unsynchronized clock)
            final leapIndicator = (data[0] >> 6) & 0x03;
            if (leapIndicator == 3) {
              completer.completeError(
                Exception(
                  'NTP server clock is unsynchronized (leap indicator: 3)',
                ),
              );
              return;
            }

            try {
              final byteData = ByteData.view(
                data.buffer,
                data.offsetInBytes,
                data.lengthInBytes,
              );
              final t3Micros = _parseTimestampMicros(byteData, 40);
              if (t3Micros == 0) {
                continue; // Discard if transmit timestamp is 0
              }

              final rawT2Micros = _parseTimestampMicros(byteData, 32);
              // Fall back to T3 if server omitted Receive Timestamp (SNTP compatibility)
              final t2Micros = rawT2Micros == 0 ? t3Micros : rawT2Micros;
              final t4Micros = t1Micros + elapsedMicros;

              final computedOffset =
                  ((t2Micros - t1Micros) + (t3Micros - t4Micros)) ~/ 2;
              final serverProcessingMicros = max(0, t3Micros - t2Micros);
              final netRttMicros = max(
                0,
                elapsedMicros - serverProcessingMicros,
              );

              final rootDelayMicros = _parseShortFormatMicros(
                byteData,
                4,
                signed: true,
              );
              final rootDispersionMicros = _parseShortFormatMicros(
                byteData,
                8,
                signed: false,
              );
              final referenceId = _parseReferenceId(data, stratum);

              completer.complete((
                offsetMicros: computedOffset,
                rttMicros: netRttMicros,
                stratum: stratum,
                leapIndicator: leapIndicator,
                referenceId: referenceId,
                rootDelayMicros: rootDelayMicros,
                rootDispersionMicros: rootDispersionMicros,
              ));
              return;
            } catch (e, stack) {
              if (!completer.isCompleted) {
                completer.completeError(e, stack);
              }
              return;
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception('Socket closed before response was received'),
            );
          }
        },
      );

      final sentBytes = socket.send(packet, ntpAddress, port);
      if (sentBytes <= 0) {
        throw Exception('Failed to send UDP packet to $server:$port');
      }

      return await completer.future.timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          throw TimeoutException('Timeout while contacting the NTP server');
        },
      );
    } finally {
      if (subscription != null) {
        await subscription.cancel();
      }
      socket.close();
    }
  }

  /// Resolves [server] to an [InternetAddress], bypassing DNS lookup if [server]
  /// is already an IPv4 or IPv6 literal.
  Future<InternetAddress> _resolveAddress() async {
    final parsedIp = InternetAddress.tryParse(server);
    if (parsedIp != null) {
      return parsedIp;
    }

    final List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(server).timeout(
        Duration(seconds: timeout),
        onTimeout: () =>
            throw TimeoutException('DNS lookup timeout for $server'),
      );
    } catch (e) {
      throw Exception('Unable to resolve NTP server address: $e');
    }
    if (addresses.isEmpty) {
      throw Exception('Unable to resolve NTP server address');
    }
    return addresses.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
  }

  /// Parses an RFC 5905 32-bit NTP short format value (16-bit seconds + 16-bit
  /// fraction) at [offset] into microseconds.
  static int _parseShortFormatMicros(
    ByteData byteData,
    int offset, {
    required bool signed,
  }) {
    final raw32 =
        signed ? byteData.getInt32(offset) : byteData.getUint32(offset);
    return (raw32 * 1000000) ~/ 65536;
  }

  /// Parses the 4-byte Reference Identifier (bytes 12–15) per RFC 5905.
  ///
  /// For Stratum 0 or 1, interprets bytes as a 4-character ASCII code
  /// (e.g. `'LOCL'`, `'GOOG'`, `'RATE'`). For Stratum >= 2, formats as IPv4.
  static String _parseReferenceId(Uint8List data, int stratum) {
    if (stratum <= 1) {
      final chars = <int>[];
      for (var i = 12; i < 16; i++) {
        final byte = data[i];
        if (byte > 0x20 && byte <= 0x7E) {
          chars.add(byte);
        }
      }
      return String.fromCharCodes(chars);
    }
    return '${data[12]}.${data[13]}.${data[14]}.${data[15]}';
  }

  /// Builds a 48-byte NTP request packet according to the protocol specification (RFC 5905).
  static Uint8List buildNtpPacket(DateTime originateTime) {
    final packet = Uint8List(48);
    // LI = 0 (no warning), VN = 3 (version 3), Mode = 3 (client)
    packet[0] = 0x1B;

    final byteData = ByteData.view(packet.buffer);
    writeNtpTimestamp(byteData, 40, originateTime);

    // RFC 5905 recommends randomizing the last byte of the transmit timestamp
    // to prevent off-path spoofing attacks.
    packet[47] = _random.nextInt(256);

    return packet;
  }

  /// Writes an NTP 64-bit timestamp into [data] starting at [offset] using
  /// pure 64-bit integer arithmetic.
  static void writeNtpTimestamp(ByteData data, int offset, DateTime time) {
    final microsSinceUnix = time.toUtc().microsecondsSinceEpoch;
    final secondsSinceUnix = microsSinceUnix ~/ 1000000;
    final microsRemainder = microsSinceUnix % 1000000;

    final ntpSeconds = (secondsSinceUnix + _ntpEpochOffset) & 0xFFFFFFFF;
    final fractional =
        (((microsRemainder * 0x100000000) + 500000) ~/ 1000000) & 0xFFFFFFFF;

    data.setUint32(offset, ntpSeconds);
    data.setUint32(offset + 4, fractional);
  }

  /// Verifies that the Origin Timestamp in the response (bytes 24-31) matches
  /// the Transmit Timestamp sent in the request (bytes 40-47).
  static bool matchesOriginTimestamp(Uint8List response, Uint8List request) {
    if (response.length < 32 || request.length < 48) return false;
    for (var i = 0; i < 8; i++) {
      if (response[24 + i] != request[40 + i]) {
        return false;
      }
    }
    return true;
  }

  /// Extracts a 64-bit NTP timestamp at [offset] directly as microseconds
  /// since Unix epoch using pure integer arithmetic and RFC 4330 Era 1 support.
  static int _parseTimestampMicros(ByteData byteData, int offset) {
    final ntpSeconds = byteData.getUint32(offset);
    final fractional = byteData.getUint32(offset + 4);

    if (ntpSeconds == 0 && fractional == 0) {
      return 0;
    }

    final int unixSeconds;
    if (ntpSeconds >= _ntpEpochOffset) {
      // Era 0 (1970 - 2036)
      unixSeconds = ntpSeconds - _ntpEpochOffset;
    } else {
      // Era 1 (2036 - 2172) per RFC 4330 / RFC 5905
      unixSeconds = (ntpSeconds + 0x100000000) - _ntpEpochOffset;
    }

    final micros = ((fractional * 1000000) + 0x80000000) ~/ 0x100000000;
    return unixSeconds * 1000000 + micros;
  }

  /// Parses the NTP server's response and extracts the Origin (T1), Receive (T2),
  /// and Transmit (T3) timestamps, with RFC 4330 Era 1 (2036 rollover) support.
  ///
  /// - T1: Origin Timestamp (bytes 24-31)
  /// - T2: Receive Timestamp (bytes 32-39)
  /// - T3: Transmit Timestamp (bytes 40-47)
  static ({
    DateTime originTimestamp,
    DateTime receiveTimestamp,
    DateTime transmitTimestamp,
  }) parseNtpTimestamps(Uint8List data) {
    if (data.length < 48) {
      throw Exception(
        'Malformed NTP response packet: length is ${data.length}',
      );
    }
    final byteData =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

    return (
      originTimestamp: DateTime.fromMicrosecondsSinceEpoch(
        _parseTimestampMicros(byteData, 24),
        isUtc: true,
      ),
      receiveTimestamp: DateTime.fromMicrosecondsSinceEpoch(
        _parseTimestampMicros(byteData, 32),
        isUtc: true,
      ),
      transmitTimestamp: DateTime.fromMicrosecondsSinceEpoch(
        _parseTimestampMicros(byteData, 40),
        isUtc: true,
      ),
    );
  }
}
