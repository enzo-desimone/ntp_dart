/// Base class for platform-specific NTP (Network Time Protocol) clients.
///
/// This abstract class defines the common configuration parameters and
/// interface for retrieving the current UTC time from an NTP source.
/// Concrete implementations (e.g., for mobile/desktop using UDP sockets,
/// or for web using HTTP APIs) should extend this class and provide the
/// platform-specific logic in the [now] method.
abstract class NtpBase {
  /// The hostname or IP address of the NTP server to query.
  ///
  /// Defaults to `'pool.ntp.org'`, which is a publicly accessible NTP pool.
  final String server;

  /// The UDP port used to communicate with the NTP server.
  ///
  /// Defaults to `123`, the standard port for NTP.
  final int port;

  /// The timeout in seconds for the time retrieval operation.
  ///
  /// If the operation does not complete within this period, an
  /// implementation should throw an [Exception] or otherwise indicate
  /// a timeout error.
  final int timeout;

  /// Creates a new [NtpBase] instance with optional configuration parameters.
  ///
  /// All parameters are optional and have sensible defaults:
  /// - [server] defaults to `'pool.ntp.org'`
  /// - [port] defaults to `123`
  /// - [timeout] defaults to `5` seconds
  const NtpBase({
    this.server = 'pool.ntp.org',
    this.port = 123,
    this.timeout = 5,
  });

  /// Retrieves the current UTC [DateTime] from the configured NTP source.
  ///
  /// This method must be implemented by concrete subclasses to perform the
  /// actual network request and parse the server response.
  Future<DateTime> now();
}
