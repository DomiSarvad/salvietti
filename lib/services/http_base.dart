// El cliente HTTP de verdad que usa ClienteOffline por debajo. En escritorio y
// celular (dart:io) lleva un tiempo máximo para CONECTAR (ver http_base_io);
// en web el navegador maneja la conexión y se usa el cliente común.
export 'http_base_stub.dart' if (dart.library.io) 'http_base_io.dart';
