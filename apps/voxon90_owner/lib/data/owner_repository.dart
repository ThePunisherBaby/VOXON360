/// Negocio del dueño.
class Business {
  const Business({required this.id, required this.name});

  final String id;
  final String name;
}

/// Caja principal vinculada al negocio.
class LinkedDevice {
  const LinkedDevice({required this.uid, required this.name, this.linkedAt});

  final String uid;
  final String name;
  final DateTime? linkedAt;
}

/// Código que se dicta en la caja principal para vincularla.
class LinkCode {
  const LinkCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// Error con un mensaje listo para mostrar.
class OwnerException implements Exception {
  const OwnerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lo que la app del dueño necesita de Firebase. Las pruebas usan una versión falsa.
abstract interface class OwnerRepository {
  /// uid del dueño con sesión, o null.
  Stream<String?> userChanges();

  String? get currentUserId;

  Future<void> signIn(String email, String password);

  Future<void> register(String email, String password);

  Future<void> signOut();

  Stream<List<Business>> businesses();

  Future<Business> createBusiness(String name);

  /// Documento suelto del negocio, p. ej. `snapshots/status`.
  Stream<Map<String, dynamic>?> document(String businessId, String path);

  /// Resúmenes diarios, del más reciente al más viejo.
  Stream<List<Map<String, dynamic>>> days(String businessId, {int limit});

  Stream<List<LinkedDevice>> devices(String businessId);

  Future<void> removeDevice(String businessId, String deviceUid);

  Future<LinkCode> createLinkCode(String businessId);
}
