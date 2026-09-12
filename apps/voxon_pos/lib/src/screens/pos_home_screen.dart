import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon_pos/src/link_store.dart';
import 'package:voxon_pos/src/pos_controller.dart';

/// Empleado adentro. Aquí entran las pantallas de venta de cada modo.
class PosHomeScreen extends ConsumerWidget {
  const PosHomeScreen({super.key, required this.link, required this.session});

  final LinkedInstance link;
  final StaffSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final branding =
        ref.watch(brandingProvider(link.instanceId)).value ??
        Branding(
          displayName: link.instanceName,
          primaryColorHex: Branding.voxon.primaryColorHex,
        );
    final mode = ref
        .watch(instanceProvider(link.instanceId))
        .value
        ?.businessMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(branding.displayName),
        actions: [
          Center(
            child: Text(
              '${session.name} · ${session.role.label}',
              key: const Key('sesion'),
            ),
          ),
          IconButton(
            tooltip: 'Salir',
            onPressed: () => ref.read(posControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandHeader(branding: branding),
            const SizedBox(height: 16),
            Text(
              'Caja lista para vender',
              style: theme.textTheme.headlineSmall,
            ),
            if (mode != null) Text(mode.name),
            Text('${link.deviceName} · caja ${link.deviceNumber}'),
          ],
        ),
      ),
    );
  }
}
