import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ntp_base.dart';

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
  });

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
    final socket = await _createSocket();
    final ntpAddress = await _resolveServerAddress();

    final packet = _buildNtpPacket();
    final T1 = DateTime.now();
    socket.send(packet, ntpAddress, port);

    final completer = Completer<DateTime>();

    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null) return;
        final T4 = DateTime.now();

        // Parse T2 (Receive Timestamp) and T3 (Transmit Timestamp)
        final timestamps = _parseNtpTimestamps(datagram.data);
        final T2 = timestamps.receiveTimestamp;
        final T3 = timestamps.transmitTimestamp;

        final offset = (T2.difference(T1).inMilliseconds +
                T3.difference(T4).inMilliseconds) /
            2;

        final correctedTime =
            DateTime.now().add(Duration(milliseconds: offset.round()));

        completer.complete(correctedTime);
        socket.close();
      }
    });

    return completer.future.timeout(Duration(seconds: timeout), onTimeout: () {
      socket.close();
      throw Exception('Timeout while contacting the NTP server');
    });
  }

  /// Opens a UDP socket for NTP communication.
  Future<RawDatagramSocket> _createSocket() {
    return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  /// Resolves the configured [server] hostname to an [InternetAddress].
  ///
  /// Throws an [Exception] if the lookup returns no results.
  Future<InternetAddress> _resolveServerAddress() async {
    final addresses = await InternetAddress.lookup(server);
    if (addresses.isEmpty) {
      throw Exception('Unable to resolve NTP server address');
    }
    return addresses.first;
  }

  /// Builds a 48-byte NTP request packet according to the protocol specification.
  Uint8List _buildNtpPacket() {
    final packet = Uint8List(48);
    packet[0] = 0x1B; // LI, VN, Mode
    return packet;
  }

  /// Parses the NTP server's response and extracts the Receive (T2) and Transmit (T3) timestamps.
  ///
  /// - T2: Receive Timestamp (bytes 32-39)
  /// - T3: Transmit Timestamp (bytes 40-47)
  ({DateTime receiveTimestamp, DateTime transmitTimestamp}) _parseNtpTimestamps(
      Uint8List data) {
    final byteData = data.buffer.asByteData();

    // Helper to parse a 64-bit NTP timestamp
    DateTime parseTimestamp(int offset) {
      final secondsSince1900 = byteData.getUint32(offset);
      final fraction = byteData.getUint32(offset + 4);

      const ntpEpochOffset = 2208988800;
      final unixSeconds = secondsSince1900 - ntpEpochOffset;

      final milliseconds = (fraction * 1000) ~/ 4294967296;

      return DateTime.fromMillisecondsSinceEpoch(
        unixSeconds * 1000 + milliseconds,
        isUtc: true,
      );
    }

    return (
      receiveTimestamp: parseTimestamp(32),
      transmitTimestamp: parseTimestamp(40),
    );
  }
}
