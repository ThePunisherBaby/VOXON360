import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/voxon_client.dart';
import 'package:voxon90/core/core_providers.dart';

const _serverUriKey = 'backend.serverUri';

/// Puerto HTTP por defecto del servidor local.
const defaultServerPort = 8090;

/// Convierte lo que escribe el usuario ("192.168.1.10" o "192.168.1.10:8090")
/// en la dirección del servidor, o null si no es válida.
Uri? parseServerAddress(String input, {int defaultPort = defaultServerPort}) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : defaultPort,
  );
}

/// Caja principal que usa este equipo. Se recuerda entre aperturas de la app.
final serverUriProvider = NotifierProvider<ServerUriController, Uri?>(
  ServerUriController.new,
);

class ServerUriController extends Notifier<Uri?> {
  @override
  Uri? build() {
    final stored = ref.watch(keyValueStoreProvider).getString(_serverUriKey);
    return stored == null ? null : Uri.tryParse(stored);
  }

  Future<void> select(Uri uri) {
    state = uri;
    return ref.read(keyValueStoreProvider).setString(_serverUriKey, '$uri');
  }

  Future<void> forget() {
    state = null;
    return ref.read(keyValueStoreProvider).remove(_serverUriKey);
  }
}

/// Cliente del servidor elegido; se cierra al cambiar de servidor.
final voxonClientProvider = Provider<VoxonClient?>((ref) {
  final uri = ref.watch(serverUriProvider);
  if (uri == null) return null;
  final client = VoxonClient(baseUri: uri);
  ref.onDispose(client.close);
  return client;
});

/// Estado del negocio en el servidor elegido.
class BusinessStatus {
  const BusinessStatus({
    required this.configured,
    this.name,
    this.businessType,
  });

  factory BusinessStatus.fromJson(Map<String, dynamic> json) {
    final business = json['business'] as Map<String, dynamic>?;
    return BusinessStatus(
      configured: json['configured'] as bool,
      name: business?['name'] as String?,
      businessType: business?['businessType'] as String?,
    );
  }

  final bool configured;
  final String? name;
  final String? businessType;
}

final businessStatusProvider = FutureProvider<BusinessStatus>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) {
    throw const BackendException(
      BackendException.offline,
      'Primero elige la caja principal',
    );
  }
  final result = await client.call('business.status');
  return BusinessStatus.fromJson(result! as Map<String, dynamic>);
});

/// Empleado con sesión abierta en este equipo. Vive solo en memoria: al
/// reiniciar la app se vuelve a pedir el PIN.
final sessionProvider = NotifierProvider<SessionController, Employee?>(
  SessionController.new,
);

class SessionController extends Notifier<Employee?> {
  StreamSubscription<void>? _expired;

  @override
  Employee? build() {
    final client = ref.watch(voxonClientProvider);
    _expired?.cancel();
    _expired = client?.sessionExpired.listen((_) => state = null);
    ref.onDispose(() => _expired?.cancel());
    return client?.employee;
  }

  Future<Employee> login(String pin) async {
    final employee = await _requireClient().login(pin);
    state = employee;
    return employee;
  }

  Future<void> logout() async {
    await ref.read(voxonClientProvider)?.logout();
    state = null;
  }

  VoxonClient _requireClient() =>
      ref.read(voxonClientProvider) ??
      (throw const BackendException(
        BackendException.offline,
        'Primero elige la caja principal',
      ));
}

/// Cambios en vivo hechos desde cualquier equipo del negocio. Si se corta la
/// conexión, se reconecta cada pocos segundos mientras haya sesión.
final backendChangesProvider = StreamProvider<BackendChange>((ref) async* {
  final client = ref.watch(voxonClientProvider);
  final employee = ref.watch(sessionProvider);
  if (client == null || employee == null) return;
  while (true) {
    try {
      yield* client.changes();
    } on BackendException catch (error) {
      if (error.isUnauthorized) return;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});
