import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:voxon_data/src/errors.dart';
import 'package:voxon_data/src/models/business.dart';
import 'package:voxon_data/src/models/pairing.dart';
import 'package:voxon_data/src/services/callables.dart';

/// Lo que hace la caja para vincularse a un negocio.
abstract interface class DeviceLinkService {
  /// Identidad anónima de esta caja en Firebase; se crea la primera vez.
  Future<String> ensureDeviceIdentity();

  /// Pide un QR para mostrar en pantalla.
  Future<PairingTicket> startPairing({required String platform});

  Stream<PairingState> watchPairing(String pairingId);

  /// Escribe el código que muestra el celular y devuelve el código de la caja.
  Future<String> confirmMobileCode({
    required String pairingId,
    required String code,
  });

  Future<void> cancelPairing(String pairingId);

  /// Vincula con el código escrito que genera VOXON 360 (sin celular).
  Future<LinkedDevice> enrollWithCode({
    required String code,
    required String platform,
  });
}

/// Lo que hace la caja ya vinculada: su marca, sus empleados y la sesión con PIN.
abstract interface class PosSessionService {
  Stream<InstanceSummary?> watchInstance(String instanceId);

  Stream<Branding> watchBranding(String instanceId);

  /// Empleados activos, por nombre.
  Stream<List<StaffMember>> watchStaff(String instanceId);

  Future<StaffSession> login({
    required String instanceId,
    required String staffId,
    required String pin,
  });

  Future<void> logout(String instanceId);
}

class FirebaseDeviceLinkService implements DeviceLinkService {
  FirebaseDeviceLinkService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  @override
  Future<String> ensureDeviceIdentity() => guard(() async {
    final current = _auth.currentUser;
    if (current != null) return current.uid;
    final credential = await _auth.signInAnonymously();
    return credential.user!.uid;
  });

  @override
  Future<PairingTicket> startPairing({required String platform}) async {
    await ensureDeviceIdentity();
    return PairingTicket.fromMap(
      await callFunction('startPairing', {'platform': platform}),
    );
  }

  @override
  Stream<PairingState> watchPairing(String pairingId) => _db
      .doc('pairings/$pairingId')
      .snapshots()
      .map((snapshot) => PairingState.fromMap(snapshot.id, snapshot.data()));

  @override
  Future<String> confirmMobileCode({
    required String pairingId,
    required String code,
  }) async {
    final result = await callFunction('confirmPairingOnDevice', {
      'pairingId': pairingId,
      'code': code,
    });
    return result['posCode'] as String;
  }

  @override
  Future<void> cancelPairing(String pairingId) async {
    await callFunction('cancelPairing', {'pairingId': pairingId});
  }

  @override
  Future<LinkedDevice> enrollWithCode({
    required String code,
    required String platform,
  }) async {
    await ensureDeviceIdentity();
    return LinkedDevice.fromMap(
      await callFunction('enrollDevice', {'code': code, 'platform': platform}),
    );
  }
}

class FirebasePosSessionService implements PosSessionService {
  FirebasePosSessionService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<InstanceSummary?> watchInstance(String instanceId) =>
      _db.doc('instances/$instanceId').snapshots().map((snapshot) {
        final data = snapshot.data();
        return data == null ? null : InstanceSummary.fromMap(snapshot.id, data);
      });

  @override
  Stream<Branding> watchBranding(String instanceId) => _db
      .doc('instances/$instanceId/settings/branding')
      .snapshots()
      .map((snapshot) => Branding.fromMap(snapshot.data()));

  @override
  Stream<List<StaffMember>> watchStaff(String instanceId) => _db
      .collection('instances/$instanceId/staff')
      .where('active', isEqualTo: true)
      .snapshots()
      .map(
        (query) => [
          for (final doc in query.docs) StaffMember.fromMap(doc.id, doc.data()),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  @override
  Future<StaffSession> login({
    required String instanceId,
    required String staffId,
    required String pin,
  }) async => StaffSession.fromMap(
    await callFunction('posLogin', {
      'instanceId': instanceId,
      'staffId': staffId,
      'pin': pin,
    }),
  );

  @override
  Future<void> logout(String instanceId) async {
    await callFunction('posLogout', {'instanceId': instanceId});
  }
}
