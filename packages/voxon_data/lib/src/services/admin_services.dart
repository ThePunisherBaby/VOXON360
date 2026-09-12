import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:voxon_data/src/errors.dart';
import 'package:voxon_data/src/models/business.dart';
import 'package:voxon_data/src/models/pairing.dart';
import 'package:voxon_data/src/pairing_qr.dart';
import 'package:voxon_data/src/services/callables.dart';

/// Entrada del dueño o administrador en VOXON 360.
abstract interface class AccountAuthService {
  /// uid con sesión, o null.
  Stream<String?> userChanges();

  String? get currentUserId;

  Future<void> signInWithEmail(String email, String password);

  Future<void> registerWithEmail(String email, String password);

  Future<void> signOut();
}

/// Lo que administra VOXON 360: cuentas, cajas y empleados.
abstract interface class AdminService {
  Future<CreatedAccount> createAccount({
    required String accountName,
    required String instanceName,
    required String mode,
  });

  Stream<InstanceSummary?> watchInstance(String instanceId);

  // --- Cajas ---

  /// Escaneó el QR de una caja: la reserva para [instanceId] y trae el código A.
  Future<ClaimedPairing> claimPairing({
    required PairingQr qr,
    required String instanceId,
    required String deviceName,
  });

  Stream<PairingState> watchPairing(String pairingId);

  /// Escribe el código B que muestra la caja: queda vinculada.
  Future<LinkedDevice> completePairing({
    required String pairingId,
    required String code,
  });

  Future<void> cancelPairing(String pairingId);

  Future<DeviceCode> createDeviceCode({
    required String instanceId,
    required String deviceName,
  });

  Stream<List<DeviceInfo>> watchDevices(String instanceId);

  Future<void> revokeDevice({
    required String instanceId,
    required String deviceUid,
  });

  // --- Empleados ---

  /// Todos los empleados, activos primero.
  Stream<List<StaffMember>> watchStaff(String instanceId);

  /// Crea (sin [staffId]) o cambia un empleado. Devuelve su id.
  Future<String> saveStaff({
    required String instanceId,
    String? staffId,
    required String name,
    required StaffRole role,
    String? pin,
    bool active = true,
  });
}

class FirebaseAccountAuthService implements AccountAuthService {
  FirebaseAccountAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Stream<String?> userChanges() => _auth.authStateChanges().map(
    (user) => user == null || user.isAnonymous ? null : user.uid,
  );

  @override
  String? get currentUserId {
    final user = _auth.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  @override
  Future<void> signInWithEmail(String email, String password) => guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> registerWithEmail(String email, String password) => guard(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> signOut() => _auth.signOut();
}

class FirebaseAdminService implements AdminService {
  FirebaseAdminService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<CreatedAccount> createAccount({
    required String accountName,
    required String instanceName,
    required String mode,
  }) async => CreatedAccount.fromMap(
    await callFunction('createAccount', {
      'accountName': accountName,
      'instanceName': instanceName,
      'mode': mode,
    }),
  );

  @override
  Stream<InstanceSummary?> watchInstance(String instanceId) =>
      _db.doc('instances/$instanceId').snapshots().map((snapshot) {
        final data = snapshot.data();
        return data == null ? null : InstanceSummary.fromMap(snapshot.id, data);
      });

  @override
  Future<ClaimedPairing> claimPairing({
    required PairingQr qr,
    required String instanceId,
    required String deviceName,
  }) async => ClaimedPairing.fromMap(
    await callFunction('claimPairing', {
      'pairingId': qr.pairingId,
      'qrToken': qr.qrToken,
      'instanceId': instanceId,
      'name': deviceName,
    }),
  );

  @override
  Stream<PairingState> watchPairing(String pairingId) => _db
      .doc('pairings/$pairingId')
      .snapshots()
      .map((snapshot) => PairingState.fromMap(snapshot.id, snapshot.data()));

  @override
  Future<LinkedDevice> completePairing({
    required String pairingId,
    required String code,
  }) async => LinkedDevice.fromMap(
    await callFunction('completePairing', {
      'pairingId': pairingId,
      'code': code,
    }),
  );

  @override
  Future<void> cancelPairing(String pairingId) async {
    await callFunction('cancelPairing', {'pairingId': pairingId});
  }

  @override
  Future<DeviceCode> createDeviceCode({
    required String instanceId,
    required String deviceName,
  }) async => DeviceCode.fromMap(
    await callFunction('createDeviceCode', {
      'instanceId': instanceId,
      'name': deviceName,
    }),
  );

  @override
  Stream<List<DeviceInfo>> watchDevices(String instanceId) => _db
      .collection('instances/$instanceId/devices')
      .snapshots()
      .map(
        (query) =>
            [
              for (final doc in query.docs)
                DeviceInfo.fromMap(doc.id, doc.data()),
            ]..sort((a, b) {
              if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
              return a.number.compareTo(b.number);
            }),
      );

  @override
  Future<void> revokeDevice({
    required String instanceId,
    required String deviceUid,
  }) async {
    await callFunction('revokeDevice', {
      'instanceId': instanceId,
      'deviceUid': deviceUid,
    });
  }

  @override
  Stream<List<StaffMember>> watchStaff(String instanceId) => _db
      .collection('instances/$instanceId/staff')
      .snapshots()
      .map(
        (query) =>
            [
              for (final doc in query.docs)
                StaffMember.fromMap(doc.id, doc.data()),
            ]..sort((a, b) {
              if (a.active != b.active) return a.active ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            }),
      );

  @override
  Future<String> saveStaff({
    required String instanceId,
    String? staffId,
    required String name,
    required StaffRole role,
    String? pin,
    bool active = true,
  }) async {
    final result = await callFunction('saveStaff', {
      'instanceId': instanceId,
      'staffId': ?staffId,
      'name': name,
      'role': role.name,
      'pin': ?pin,
      'active': active,
    });
    return result['staffId'] as String;
  }
}
