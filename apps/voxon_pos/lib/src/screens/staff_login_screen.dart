import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon_pos/src/link_store.dart';
import 'package:voxon_pos/src/pos_controller.dart';

/// Caja vinculada y bloqueada: el empleado toca su nombre y escribe su PIN.
class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key, required this.link});

  final LinkedInstance link;

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  StaffMember? _selected;
  String? _error;
  bool _busy = false;

  Future<void> _login(String pin) async {
    final member = _selected;
    if (member == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(posControllerProvider.notifier).login(member, pin);
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instanceId = widget.link.instanceId;
    final branding = ref.watch(brandingProvider(instanceId));
    final staff = ref.watch(staffProvider(instanceId));

    if (branding.hasError && !branding.hasValue) {
      return _NoAccess(
        onRetry: () {
          ref.invalidate(brandingProvider(instanceId));
          ref.invalidate(staffProvider(instanceId));
        },
        onRelink: () => ref.read(posControllerProvider.notifier).unlink(),
      );
    }

    final brand =
        branding.value ??
        Branding(
          displayName: widget.link.instanceName,
          primaryColorHex: Branding.voxon.primaryColorHex,
        );
    final member = _selected;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandHeader(branding: brand, size: member == null ? 88 : 56),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.link.deviceName} · caja ${widget.link.deviceNumber}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  if (member == null) ...[
                    Text('Toca tu nombre', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    staff.when(
                      loading: () => const CircularProgressIndicator(),
                      error: (error, _) => Text('$error'),
                      data: (members) => StaffPicker(
                        staff: members,
                        onSelected: (chosen) => setState(() {
                          _selected = chosen;
                          _error = null;
                        }),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Hola, ${member.name}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Text('Escribe tu PIN'),
                    const SizedBox(height: 8),
                    NumberPad(
                      key: ValueKey(member.id),
                      length: 6,
                      minLength: 4,
                      obscure: true,
                      busy: _busy,
                      errorText: _error,
                      onCompleted: _login,
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _selected = null;
                              _error = null;
                            }),
                      child: const Text('No soy yo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onRetry, required this.onRelink});

  final VoidCallback onRetry;
  final VoidCallback onRelink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 56),
              const SizedBox(height: 16),
              const Text(
                'No se pudo abrir el negocio.\nSi el dueño desactivó esta caja, vincúlala de nuevo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onRelink,
                child: const Text('Vincular de nuevo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
