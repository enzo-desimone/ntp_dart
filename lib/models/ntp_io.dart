import 'dart:async';
import 'dart:io';
import 'dart:typed_data';


/// A simple NTP client for fetching the current UTC time from an NTP server.
class NtpClient {
  /// NTP server hostname or IP address.
  final String server;

  /// NTP server port (default: 123).
  final int port;

  /// Timeout in seconds for the network request.
  final int timeout;

  NtpClient({
    this.server = 'pool.ntp.org',
    this.port = 123,
    this.timeout = 5,
  });

  /// Returns the current UTC [DateTime] as provided by the NTP server.
  Future<DateTime> now() async {
    final socket = await _createSocket();
    final ntpAddress = await _resolveServerAddress();

    final packet = _buildNtpPacket();
    socket.send(packet, ntpAddress, port);

    final completer = Completer<DateTime>();

    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null) return;
        final dateTime = _parseNtpResponse(datagram.data);
        completer.complete(dateTime);
        socket.close();
      }
    });

    return completer.future.timeout(Duration(seconds: timeout), onTimeout: () {
      socket.close();
      throw Exception('Timeout while contacting the NTP server');
    });
  }

  /// Opens a UDP socket for communication.
  Future<RawDatagramSocket> _createSocket() {
    return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  /// Resolves the NTP server hostname to an [InternetAddress].
  Future<InternetAddress> _resolveServerAddress() async {
    final addresses = await InternetAddress.lookup(server);
    if (addresses.isEmpty) {
      throw Exception('Unable to resolve NTP server address');
    }
    return addresses.first;
  }

  /// Builds a 48-byte NTP request packet.
  Uint8List _buildNtpPacket() {
    final packet = Uint8List(48);
    packet[0] = 0x1B;
    return packet;
  }

  /// Parses the NTP response and extracts the UTC [DateTime].
  DateTime _parseNtpResponse(Uint8List data) {
    final secondsSince1900 = data.buffer.asByteData().getUint32(40);
    const ntpEpochOffset = 2208988800;
    final unixSeconds = secondsSince1900 - ntpEpochOffset;
    return DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  }
}
