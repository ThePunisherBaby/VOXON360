import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:voxon90_owner/data/owner_repository.dart';
import 'package:voxon90_owner/domain/link_code.dart';

/// Lectura de los resúmenes que sube la caja principal. El dueño solo escribe
/// su negocio, los códigos de vínculo y el retiro de una caja.
class FirebaseOwnerRepository implements OwnerRepository {
  FirebaseOwnerRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Stream<String?> userChanges() =>
      _auth.authStateChanges().map((user) => user?.uid);

  @override
  Future<void> signIn(String email, String password) => _run(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> register(String email, String password) => _run(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Stream<List<Business>> businesses() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('businesses')
        .where('ownerUids', arrayContains: uid)
        .snapshots()
        .map(
          (query) => [
            for (final document in query.docs)
              Business(
                id: document.id,
                name: document.data()['name'] as String? ?? 'Mi negocio',
              ),
          ],
        );
  }

  @override
  Future<Business> createBusiness(String name) async {
    final uid = _requireUser();
    final document = _db.collection('businesses').doc();
    await _run(
      () => document.set({
        'name': name,
        'ownerUids': [uid],
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
    return Business(id: document.id, name: name);
  }

  @override
  Stream<Map<String, dynamic>?> document(String businessId, String path) => _db
      .doc('businesses/$businessId/$path')
      .snapshots()
      .map((doc) => _plainDocument(doc.data()));

  @override
  Stream<List<Map<String, dynamic>>> days(
    String businessId, {
    int limit = 14,
  }) => _db
      .collection('businesses/$businessId/days')
      .orderBy(FieldPath.documentId, descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (query) => [
          for (final document in query.docs) _plainDocument(document.data())!,
        ],
      );

  @override
  Stream<List<LinkedDevice>> devices(String businessId) => _db
      .collection('businesses/$businessId/devices')
      .snapshots()
      .map(
        (query) => [
          for (final document in query.docs)
            LinkedDevice(
              uid: document.id,
              name: document.data()['name'] as String? ?? 'Caja principal',
              linkedAt: (document.data()['linkedAt'] as Timestamp?)?.toDate(),
            ),
        ],
      );

  @override
  Future<void> removeDevice(String businessId, String deviceUid) =>
      _run(() => _db.doc('businesses/$businessId/devices/$deviceUid').delete());

  @override
  Future<LinkCode> createLinkCode(String businessId) async {
    final uid = _requireUser();
    final code = generateLinkCode();
    final expiresAt = DateTime.now().add(linkCodeLifetime);
    await _run(
      () => _db.doc('linkCodes/$code').set({
        'businessId': businessId,
        'ownerUid': uid,
        'expiresAt': Timestamp.fromDate(expiresAt),
      }),
    );
    return LinkCode(code: code, expiresAt: expiresAt);
  }

  String _requireUser() =>
      currentUserId ??
      (throw const OwnerException('Entra con tu cuenta primero'));

  /// Firestore devuelve Timestamp; el resto de la app trabaja con DateTime.
  static Map<String, dynamic>? _plainDocument(Map<String, dynamic>? data) =>
      data == null ? null : (_plain(data)! as Map).cast<String, dynamic>();

  static Object? _plain(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    Map() => {
      for (final entry in value.entries) '${entry.key}': _plain(entry.value),
    },
    List() => [for (final item in value) _plain(item)],
    _ => value,
  };

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw OwnerException(_authMessage(error.code));
    } on FirebaseException catch (error) {
      throw OwnerException(
        error.code == 'permission-denied'
            ? 'No tienes permiso para eso'
            : 'Firebase: ${error.message ?? error.code}',
      );
    }
  }

  static String _authMessage(String code) => switch (code) {
    'invalid-email' => 'El correo no es válido',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Correo o contraseña incorrectos',
    'email-already-in-use' => 'Ese correo ya tiene una cuenta',
    'weak-password' => 'La contraseña debe tener al menos 6 caracteres',
    'network-request-failed' => 'Sin internet',
    'too-many-requests' => 'Demasiados intentos; espera un momento',
    _ => 'No se pudo completar ($code)',
  };
}
