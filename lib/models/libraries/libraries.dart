/// Platform-specific NTP client exports (UDP on IO, HTTP on Web/WASM).
library;

export 'ntp_base.dart';
export 'ntp_io.dart' if (dart.library.js_interop) 'ntp_web.dart';
