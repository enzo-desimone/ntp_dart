import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ntp_dart/models/libraries/ntp_base.dart';

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

  /// Retrieves the current UTC [DateTime] from the configured NTP server.
  ///
  /// Opens a UDP socket, sends a standard 48-byte NTP request packet,
  /// waits for a response, and parses the server's transmit timestamp
  /// into a [DateTime] object.
  ///
  /// Throws an [Exception] if the hostname cannot be resolved, if the
  /// server does not respond within [timeout] seconds, or if the packet
  /// format is invalid.
  @override
  Future<DateTime> now() async {
    final List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(server);
    } catch (e) {
      throw Exception('Unable to resolve NTP server address: $e');
    }
    if (addresses.isEmpty) {
      throw Exception('Unable to resolve NTP server address');
    }
    final ntpAddress = addresses.first;

    final bindAddress = ntpAddress.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;

    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(bindAddress, 0);
    } catch (e) {
      throw Exception('Could not bind UDP socket: $e');
    }

    final completer = Completer<DateTime>();
    StreamSubscription<RawSocketEvent>? subscription;

    try {
      final originateTime = DateTime.now().toUtc();
      final packet = _buildNtpPacket(originateTime);
      socket.send(packet, ntpAddress, port);

      subscription = socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram == null) return;
            final destinationTime = DateTime.now().toUtc();

            try {
              final timestamps = _parseNtpTimestamps(datagram.data);
              final t2 = timestamps.receiveTimestamp;
              final t3 = timestamps.transmitTimestamp;

              final offsetMicros = ((t2.microsecondsSinceEpoch -
                          originateTime.microsecondsSinceEpoch) +
                      (t3.microsecondsSinceEpoch -
                          destinationTime.microsecondsSinceEpoch)) ~/
                  2;

              final correctedTime =
                  DateTime.now().add(Duration(microseconds: offsetMicros));

              completer.complete(
                isUtc ? correctedTime.toUtc() : correctedTime.toLocal(),
              );
            } catch (e, stack) {
              completer.completeError(e, stack);
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

  /// Builds a 48-byte NTP request packet according to the protocol specification (RFC 5905).
  Uint8List _buildNtpPacket(DateTime originateTime) {
    final packet = Uint8List(48);
    // LI = 0 (no warning), VN = 3 (version 3), Mode = 3 (client)
    packet[0] = 0x1B;

    final byteData = ByteData.view(packet.buffer);
    _writeNtpTimestamp(byteData, 40, originateTime);

    // RFC 5905 recommends randomizing the last byte of the transmit timestamp
    // to prevent off-path spoofing attacks.
    packet[47] = _random.nextInt(256);

    return packet;
  }

  /// Writes an NTP 64-bit timestamp into [data] starting at [offset].
  void _writeNtpTimestamp(ByteData data, int offset, DateTime time) {
    const ntpEpochOffset = 2208988800; // seconds between 1900 and 1970
    final microsSinceUnix = time.toUtc().microsecondsSinceEpoch;
    final secondsSinceUnix = microsSinceUnix ~/ 1000000;
    final microsRemainder = microsSinceUnix % 1000000;

    final ntpSeconds = (secondsSinceUnix + ntpEpochOffset) & 0xFFFFFFFF;
    final fractional =
        ((microsRemainder / 1000000) * 0x100000000).round() & 0xFFFFFFFF;

    data.setUint32(offset, ntpSeconds);
    data.setUint32(offset + 4, fractional);
  }

  /// Parses the NTP server's response and extracts the Receive (T2) and Transmit (T3) timestamps.
  ///
  /// - T2: Receive Timestamp (bytes 32-39)
  /// - T3: Transmit Timestamp (bytes 40-47)
  ({DateTime receiveTimestamp, DateTime transmitTimestamp}) _parseNtpTimestamps(
    Uint8List data,
  ) {
    if (data.length < 48) {
      throw Exception(
        'Malformed NTP response packet: length is ${data.length}',
      );
    }
    final byteData =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

    // Helper to parse a 64-bit NTP timestamp with microsecond precision
    DateTime parseTimestamp(int offset) {
      final ntpSeconds = byteData.getUint32(offset);
      final fractional = byteData.getUint32(offset + 4);

      if (ntpSeconds == 0 && fractional == 0) {
        return DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      }

      const ntpEpochOffset = 2208988800;
      final unixSeconds = ntpSeconds - ntpEpochOffset;
      final micros = (fractional / 0x100000000 * 1000000).round();

      return DateTime.fromMicrosecondsSinceEpoch(
        unixSeconds * 1000000 + micros,
        isUtc: true,
      );
    }

    return (
      receiveTimestamp: parseTimestamp(32),
      transmitTimestamp: parseTimestamp(40),
    );
  }
}
