import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/server_discovery.dart';
import 'package:voxon90/core/backend/voxon_client.dart';

typedef ServerFinder = Future<List<DiscoveredServer>> Function();
typedef ServerProbe = Future<void> Function(Uri uri);

/// Busca la caja principal en el WiFi. Las pruebas lo reemplazan.
final serverFinderProvider = Provider<ServerFinder>(
  (ref) =>
      () => ServerDiscovery.find(),
);

/// Comprueba que en esa dirección responde un servidor de VOXON90.
final serverProbeProvider = Provider<ServerProbe>(
  (ref) => (uri) async {
    final client = VoxonClient(
      baseUri: uri,
      timeout: const Duration(seconds: 5),
    );
    try {
      await client.health();
    } finally {
      client.close();
    }
  },
);
