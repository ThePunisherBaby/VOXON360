import 'dart:async';

import 'package:voxon_data/voxon_data.dart';

/// Emite el valor actual y lo repite cada vez que [changes] avisa.
Stream<T> live<T>(T Function() current, StreamController<void> changes) async* {
  yield current();
  await for (final _ in changes.stream) {
    yield current();
  }
}

/// Cuenta de mentira: la contraseña buena es `secreto1`.
class FakeAccountAuthService implements AccountAuthService {
  FakeAccountAuthService({this.currentUserId, this.canUseGoogle = false});

  final _changes = StreamController<void>.broadcast();

  @override
  String? currentUserId;

  @override
  final bool canUseGoogle;

  void _signIn() {
    currentUserId = 'dueno';
    _changes.add(null);
  }

  @override
  Stream<String?> userChanges() => live(() => currentUserId, _changes);

  @override
  Future<void> signInWithEmail(String email, String password) async {
    if (password != 'secreto1') {
      throw const VoxonException(
        'invalid-credential',
        'Correo o contraseña incorrectos',
      );
    }
    _signIn();
  }

  @override
  Future<void> registerWithEmail(String email, String password) async =>
      _signIn();

  @override
  Future<void> signInWithGoogle() async => _signIn();

  @override
  Future<void> signOut() async {
    currentUserId = null;
    _changes.add(null);
  }
}

/// Servidor de mentira para VOXON 360. La caja "muestra" [posCode].
class FakeAdminService implements AdminService {
  final _changes = StreamController<void>.broadcast();
  final pairing = StreamController<PairingState>.broadcast();

  List<MyInstance> instances = const [];
  List<DeviceInfo> devices = const [
    DeviceInfo(
      uid: 'd1',
      name: 'Caja mostrador',
      platform: 'windows',
      number: 1,
      status: 'active',
      enrolledWith: 'qr',
    ),
  ];
  List<StaffMember> staff = const [];

  final created = <({String accountName, String instanceName, String mode})>[];
  final claimedNames = <String>[];
  final revoked = <String>[];
  final savedPins = <String, String?>{};
  String mobileCode = '482913';
  String posCode = '175204';

  void _changed() => _changes.add(null);

  @override
  Future<CreatedAccount> createAccount({
    required String accountName,
    required String instanceName,
    required String mode,
  }) async {
    created.add((
      accountName: accountName,
      instanceName: instanceName,
      mode: mode,
    ));
    // Lo que hace el servidor: el negocio aparece en la lista del dueño.
    instances = [
      MyInstance(
        id: 'i1',
        accountId: 'c1',
        name: instanceName,
        mode: mode,
        role: StaffRole.owner,
      ),
    ];
    _changed();
    return const CreatedAccount(accountId: 'c1', instanceId: 'i1');
  }

  @override
  Stream<InstanceSummary?> watchInstance(String instanceId) =>
      const Stream.empty();

  @override
  Stream<List<MyInstance>> watchMyInstances(String uid) =>
      live(() => instances, _changes);

  @override
  Future<ClaimedPairing> claimPairing({
    required PairingQr qr,
    required String instanceId,
    required String deviceName,
  }) async {
    claimedNames.add(deviceName);
    return ClaimedPairing(
      mobileCode: mobileCode,
      instanceName: 'La Fonda',
      deviceName: deviceName,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Stream<PairingState> watchPairing(String pairingId) => pairing.stream;

  @override
  Future<LinkedDevice> completePairing({
    required String pairingId,
    required String code,
  }) async {
    if (code != posCode) {
      throw const VoxonException('permission-denied', 'Código incorrecto');
    }
    return LinkedDevice(
      instanceId: 'i1',
      instanceName: 'La Fonda',
      mode: 'restaurant',
      deviceName: claimedNames.last,
      deviceNumber: 1,
    );
  }

  @override
  Future<void> cancelPairing(String pairingId) async {}

  @override
  Future<DeviceCode> createDeviceCode({
    required String instanceId,
    required String deviceName,
  }) async => DeviceCode(
    code: 'ABCD2345',
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
    instanceName: 'La Fonda',
    deviceName: deviceName,
  );

  @override
  Stream<List<DeviceInfo>> watchDevices(String instanceId) =>
      live(() => devices, _changes);

  @override
  Future<void> revokeDevice({
    required String instanceId,
    required String deviceUid,
  }) async {
    revoked.add(deviceUid);
    devices = [
      for (final device in devices)
        device.uid == deviceUid
            ? DeviceInfo(
                uid: device.uid,
                name: device.name,
                platform: device.platform,
                number: device.number,
                status: 'revoked',
                enrolledWith: device.enrolledWith,
              )
            : device,
    ];
    _changed();
  }

  @override
  Stream<List<StaffMember>> watchStaff(String instanceId) =>
      live(() => staff, _changes);

  @override
  Future<String> saveStaff({
    required String instanceId,
    String? staffId,
    required String name,
    required StaffRole role,
    String? pin,
    bool active = true,
  }) async {
    final id = staffId ?? 's${staff.length + 1}';
    savedPins[id] = pin;
    staff = [
      ...staff.where((member) => member.id != id),
      StaffMember(id: id, name: name, role: role, active: active),
    ];
    _changed();
    return id;
  }
}
