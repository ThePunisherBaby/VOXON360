import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon360/src/providers.dart';
import 'package:voxon360/src/screens/pairing_flow_screen.dart';
import 'package:voxon360/src/screens/scan_pairing_screen.dart';

/// Cajas con VOXON POS del negocio: vincular con QR o con código, y desactivar.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key, required this.instanceId});

  final String instanceId;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    if (!ref.read(canScanProvider)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Escanear desde el celular'),
          content: const Text(
            'Abre VOXON 360 en tu celular, entra a Cajas → Vincular con QR y apunta '
            'la cámara a la caja. Desde aquí puedes usar un código de caja.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ScanPairingScreen(
          instanceId: instanceId,
          onQr: (qr) => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (context) =>
                  PairingFlowScreen(instanceId: instanceId, qr: qr),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createCode(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _DeviceNameDialog(),
    );
    if (name == null || !context.mounted) return;
    try {
      final code = await ref
          .read(adminServiceProvider)
          .createDeviceCode(instanceId: instanceId, deviceName: name);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Código para ${code.deviceName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'En la caja: «No tengo celular: usar un código de caja».',
              ),
              const SizedBox(height: 16),
              SelectableText(
                code.formatted,
                key: const Key('codigo-caja'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Sirve una sola vez durante 24 horas.'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    } on VoxonException catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DeviceInfo device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Desactivar ${device.name}?'),
        content: const Text(
          'La caja deja de ver el negocio y de vender. Para volver a usarla hay que vincularla de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(adminServiceProvider)
          .revokeDevice(instanceId: instanceId, deviceUid: device.uid);
    } on VoxonException catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devices = ref.watch(devicesProvider(instanceId));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Cajas', style: theme.textTheme.headlineSmall),
        const Text(
          'Instala VOXON POS en cada caja y vincúlala con tu celular. Toma el nombre, el logo y los colores de tu negocio.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => _scan(context, ref),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Vincular con QR'),
            ),
            OutlinedButton.icon(
              onPressed: () => _createCode(context, ref),
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Agregar con código'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
          data: (items) => items.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no hay cajas vinculadas.'),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final device in items)
                        ListTile(
                          leading: Icon(
                            device.platform == 'android' ||
                                    device.platform == 'ios'
                                ? Icons.tablet_android
                                : Icons.desktop_windows_outlined,
                          ),
                          title: Text(device.name),
                          subtitle: Text(
                            'Caja ${device.number} · '
                            '${device.enrolledWith == 'qr' ? 'vinculada con QR' : 'vinculada con código'}'
                            '${device.isActive ? '' : ' · desactivada'}',
                          ),
                          trailing: device.isActive
                              ? IconButton(
                                  tooltip: 'Desactivar',
                                  onPressed: () =>
                                      _revoke(context, ref, device),
                                  icon: const Icon(Icons.link_off),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeviceNameDialog extends StatefulWidget {
  const _DeviceNameDialog();

  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  final _name = TextEditingController(text: 'Caja');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva caja'),
      content: TextField(
        key: const Key('nombre-caja'),
        controller: _name,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Nombre de la caja'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            Navigator.pop(context, name.isEmpty ? 'Caja' : name);
          },
          child: const Text('Crear código'),
        ),
      ],
    );
  }
}
