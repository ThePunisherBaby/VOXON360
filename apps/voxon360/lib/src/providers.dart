import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

/// Servicios que main.dart conecta con Firebase y las pruebas con versiones falsas.
final accountAuthServiceProvider = Provider<AccountAuthService>(
  (ref) => throw UnimplementedError('Falta accountAuthServiceProvider'),
);

final adminServiceProvider = Provider<AdminService>(
  (ref) => throw UnimplementedError('Falta adminServiceProvider'),
);

/// Solo los celulares y tablets tienen cámara para escanear el QR de la caja.
final canScanProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
);

final userIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(accountAuthServiceProvider).userChanges(),
);

/// Negocios donde trabaja la persona con sesión.
final myInstancesProvider = StreamProvider<List<MyInstance>>((ref) {
  final uid = ref.watch(userIdProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(adminServiceProvider).watchMyInstances(uid);
});

/// Negocio que se está administrando; null = el primero.
final selectedInstanceProvider = NotifierProvider<SelectedInstance, String?>(
  SelectedInstance.new,
);

class SelectedInstance extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? instanceId) => state = instanceId;
}

final devicesProvider = StreamProvider.family<List<DeviceInfo>, String>(
  (ref, instanceId) => ref.watch(adminServiceProvider).watchDevices(instanceId),
);

final staffListProvider = StreamProvider.family<List<StaffMember>, String>(
  (ref, instanceId) => ref.watch(adminServiceProvider).watchStaff(instanceId),
);
