import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Caja principal encontrada en la red local.
class DiscoveredServer {
  const DiscoveredServer({
    required this.name,
    required this.address,
    required this.httpPort,
    required this.version,
  });

  /// Nombre del negocio, o null si aún no está configurado.
  final String? name;
  final InternetAddress address;
  final int httpPort;
  final String version;

  Uri get baseUri => Uri(scheme: 'http', host: address.address, port: httpPort);
}

/// Busca el servidor de VOXON90 en el WiFi del negocio, sin internet: envía
/// `VOXON90_DISCOVER` por UDP en difusión y reúne las respuestas.
abstract final class ServerDiscovery {
  static const defaultPort = 47800;
  static const request = 'VOXON90_DISCOVER';

  static Future<List<DiscoveredServer>> find({
    Duration wait = const Duration(seconds: 2),
    int port = defaultPort,
    InternetAddress? target,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final found = <String, DiscoveredServer>{};

    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final server = _parse(datagram);
      if (server != null) {
        found['${server.address.address}:${server.httpPort}'] = server;
      }
    });

    try {
      socket.send(
        utf8.encode(request),
        target ?? InternetAddress('255.255.255.255'),
        port,
      );
      await Future<void>.delayed(wait);
    } finally {
      await subscription.cancel();
      socket.close();
    }
    return found.values.toList();
  }

  static DiscoveredServer? _parse(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic> || json['service'] != 'voxon90') {
        return null;
      }
      return DiscoveredServer(
        name: json['name'] as String?,
        address: datagram.address,
        httpPort: json['httpPort'] as int,
        version: json['version'] as String? ?? '',
      );
    } on Object {
      return null;
    }
  }
}
