import 'dart:async';

import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_domain/voxon_domain.dart';

/// Servidor de mentira para la vinculación: el celular "da" [mobileCode] y la
/// caja recibe [posCode].
class FakeDeviceLinkService implements DeviceLinkService {
  final pairing = StreamController<PairingState>.broadcast();
  final platforms = <String>[];
  String mobileCode = '482913';
  String posCode = '175204';
  String? enrolledCode;
  LinkedDevice? enrollResult;

  @override
  Future<String> ensureDeviceIdentity() async => 'caja-uid';

  @override
  Future<PairingTicket> startPairing({required String platform}) async {
    platforms.add(platform);
    return PairingTicket(
      pairingId: 'Ab3xY9kLmN0pQrStUvWx',
      qrToken: 'k8J2-mZ_q0aB7cD9eF1gH3iJ5kL7mN9oP1qR3sT5uV7',
      qr: 'voxon://pair?p=Ab3xY9kLmN0pQrStUvWx&t=k8J2-mZ_q0aB7cD9eF1gH3iJ5kL7mN9oP1qR3sT5uV7',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Stream<PairingState> watchPairing(String pairingId) => pairing.stream;

  @override
  Future<String> confirmMobileCode({
    required String pairingId,
    required String code,
  }) async {
    if (code != mobileCode) {
      throw const VoxonException('permission-denied', 'Código incorrecto');
    }
    return posCode;
  }

  @override
  Future<void> cancelPairing(String pairingId) async {}

  @override
  Future<LinkedDevice> enrollWithCode({
    required String code,
    required String platform,
  }) async {
    enrolledCode = code;
    final result = enrollResult;
    if (result == null) {
      throw const VoxonException(
        'not-found',
        'Ese código no existe, ya se usó o venció.',
      );
    }
    return result;
  }
}

/// Negocio de mentira: su marca, un cajero con PIN 2468 y el registro de salidas.
class FakePosSessionService implements PosSessionService {
  Branding branding = const Branding(
    displayName: 'Colmado Don Pedro',
    primaryColorHex: '#EF6C00',
  );
  List<StaffMember> staff = const [
    StaffMember(
      id: 'luis',
      name: 'Luis Pérez',
      role: StaffRole.cashier,
      active: true,
    ),
  ];
  String pin = '2468';

  /// El dueño desactivó la caja: la caja ya no puede leer el negocio.
  bool revoked = false;
  final logouts = <String>[];

  static const _denied = VoxonException(
    'permission-denied',
    'No tienes permiso para eso',
  );

  @override
  Stream<InstanceSummary?> watchInstance(String instanceId) => revoked
      ? Stream.error(_denied)
      : Stream.value(
          InstanceSummary(
            id: instanceId,
            name: branding.displayName,
            mode: 'colmado',
            accountId: 'c1',
            modules: const {'catalog', 'credit'},
            priceMode: PriceMode.taxIncluded,
            legalTip: false,
            active: true,
          ),
        );

  @override
  Stream<Branding> watchBranding(String instanceId) =>
      revoked ? Stream.error(_denied) : Stream.value(branding);

  @override
  Stream<List<StaffMember>> watchStaff(String instanceId) =>
      revoked ? Stream.error(_denied) : Stream.value(staff);

  @override
  Future<StaffSession> login({
    required String instanceId,
    required String staffId,
    required String pin,
  }) async {
    if (pin != this.pin) {
      throw const VoxonException('permission-denied', 'PIN incorrecto');
    }
    final member = staff.firstWhere((candidate) => candidate.id == staffId);
    return StaffSession(staffId: staffId, name: member.name, role: member.role);
  }

  @override
  Future<void> logout(String instanceId) async => logouts.add(instanceId);
}
