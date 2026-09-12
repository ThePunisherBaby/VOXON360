import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon_pos/src/link_store.dart';

/// Servicios que main.dart conecta con Firebase y las pruebas con versiones falsas.
final deviceLinkServiceProvider = Provider<DeviceLinkService>(
  (ref) => throw UnimplementedError('Falta deviceLinkServiceProvider'),
);

final posSessionServiceProvider = Provider<PosSessionService>(
  (ref) => throw UnimplementedError('Falta posSessionServiceProvider'),
);

final linkStoreProvider = Provider<LinkStore>(
  (ref) => throw UnimplementedError('Falta linkStoreProvider'),
);

/// windows, android, macos… para registrar desde dónde se vinculó la caja.
final platformNameProvider = Provider<String>(
  (ref) => defaultTargetPlatform.name,
);

final brandingProvider = StreamProvider.family<Branding, String>(
  (ref, instanceId) =>
      ref.watch(posSessionServiceProvider).watchBranding(instanceId),
);

final staffProvider = StreamProvider.family<List<StaffMember>, String>(
  (ref, instanceId) =>
      ref.watch(posSessionServiceProvider).watchStaff(instanceId),
);

final instanceProvider = StreamProvider.family<InstanceSummary?, String>(
  (ref, instanceId) =>
      ref.watch(posSessionServiceProvider).watchInstance(instanceId),
);

/// En qué punto está la caja.
sealed class PosState {
  const PosState();
}

/// Leyendo si ya estaba vinculada.
final class PosLoading extends PosState {
  const PosLoading();
}

final class PosUnlinked extends PosState {
  const PosUnlinked();
}

/// Vinculada; con [session] hay un empleado adentro.
final class PosLinked extends PosState {
  const PosLinked(this.link, {this.session});

  final LinkedInstance link;
  final StaffSession? session;
}

final posControllerProvider = NotifierProvider<PosController, PosState>(
  PosController.new,
);

class PosController extends Notifier<PosState> {
  @override
  PosState build() {
    Future.microtask(_restore);
    return const PosLoading();
  }

  Future<void> _restore() async {
    final link = await ref.read(linkStoreProvider).read();
    state = link == null ? const PosUnlinked() : PosLinked(link);
  }

  /// La vinculación por QR terminó.
  Future<void> linkFromPairing(PairingState pairing) async {
    final instanceId = pairing.instanceId;
    if (instanceId == null) return;
    await _save(
      LinkedInstance(
        instanceId: instanceId,
        instanceName: pairing.instanceName ?? '',
        deviceName: pairing.deviceName ?? 'Caja',
        deviceNumber: pairing.deviceNumber ?? 0,
      ),
    );
  }

  /// Se vinculó con un código escrito.
  Future<void> linkWithDevice(LinkedDevice device) =>
      _save(LinkedInstance.fromLinkedDevice(device));

  Future<void> _save(LinkedInstance link) async {
    if (state case PosLinked(
      link: final current,
    ) when current.instanceId == link.instanceId) {
      return;
    }
    await ref.read(linkStoreProvider).save(link);
    state = PosLinked(link);
  }

  Future<StaffSession> login(StaffMember member, String pin) async {
    final current = state;
    if (current is! PosLinked) {
      throw StateError('La caja no está vinculada');
    }
    final session = await ref
        .read(posSessionServiceProvider)
        .login(
          instanceId: current.link.instanceId,
          staffId: member.id,
          pin: pin,
        );
    state = PosLinked(current.link, session: session);
    return session;
  }

  Future<void> logout() async {
    final current = state;
    if (current is! PosLinked) return;
    state = PosLinked(current.link);
    try {
      await ref.read(posSessionServiceProvider).logout(current.link.instanceId);
    } on VoxonException {
      // La caja ya se bloqueó aquí; el servidor la bloquea al volver la conexión.
    }
  }

  /// La caja fue desactivada o se quiere pasar a otro negocio.
  Future<void> unlink() async {
    await ref.read(linkStoreProvider).clear();
    state = const PosUnlinked();
  }
}
