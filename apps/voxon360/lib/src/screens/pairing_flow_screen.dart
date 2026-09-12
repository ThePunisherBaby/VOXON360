import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon360/src/providers.dart';

/// Después de escanear: reservar la caja, dar el código A y escribir el código B.
class PairingFlowScreen extends ConsumerStatefulWidget {
  const PairingFlowScreen({
    super.key,
    required this.instanceId,
    required this.qr,
  });

  final String instanceId;
  final PairingQr qr;

  @override
  ConsumerState<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends ConsumerState<PairingFlowScreen> {
  final _name = TextEditingController(text: 'Caja');
  ClaimedPairing? _claimed;
  PairingState? _pairing;
  LinkedDevice? _linked;
  StreamSubscription<PairingState>? _subscription;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _subscription?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() => _run(() async {
    final service = ref.read(adminServiceProvider);
    final name = _name.text.trim();
    final claimed = await service.claimPairing(
      qr: widget.qr,
      instanceId: widget.instanceId,
      deviceName: name.isEmpty ? 'Caja' : name,
    );
    if (!mounted) return;
    setState(() => _claimed = claimed);
    _subscription = service.watchPairing(widget.qr.pairingId).listen((pairing) {
      if (mounted) setState(() => _pairing = pairing);
    });
  });

  Future<void> _complete(String code) => _run(() async {
    final linked = await ref
        .read(adminServiceProvider)
        .completePairing(pairingId: widget.qr.pairingId, code: code);
    if (mounted) setState(() => _linked = linked);
  });

  Widget _step(ThemeData theme) {
    final linked = _linked;
    final pairing = _pairing;
    if (linked != null || pairing?.status == PairingStatus.linked) {
      return Column(
        children: [
          Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Caja vinculada', style: theme.textTheme.headlineSmall),
          Text(
            '${linked?.deviceName ?? pairing?.deviceName ?? 'Caja'} · caja '
            '${linked?.deviceNumber ?? pairing?.deviceNumber ?? ''}',
          ),
          const SizedBox(height: 16),
          const Text(
            'Ya muestra tu negocio. Tus empleados entran con su PIN.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Listo'),
          ),
        ],
      );
    }

    final claimed = _claimed;
    if (claimed == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Encontramos una caja', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Ponle un nombre para reconocerla, como «Caja mostrador».',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('nombre-caja-qr'),
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Nombre de la caja',
              errorText: _error,
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _claim,
            child: const Text('Reservar la caja'),
          ),
        ],
      );
    }

    return switch (pairing?.status ?? PairingStatus.claimed) {
      PairingStatus.waiting || PairingStatus.claimed => Column(
        children: [
          CodeDisplay(
            code: claimed.mobileCode,
            instruction: 'Escribe este código en la caja',
          ),
          const SizedBox(height: 16),
          const Text('Esperando que la caja lo confirme…'),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ),
      PairingStatus.deviceConfirmed => Column(
        children: [
          Text(
            'Escribe el código que ahora muestra la caja',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          NumberPad(
            length: 6,
            busy: _busy,
            errorText: _error,
            onCompleted: _complete,
          ),
        ],
      ),
      PairingStatus.linked => const SizedBox.shrink(),
      PairingStatus.failed => const _Ended(
        message:
            'Demasiados códigos incorrectos. Genera un QR nuevo en la caja.',
      ),
      PairingStatus.cancelled => const _Ended(
        message: 'Se canceló la vinculación.',
      ),
      PairingStatus.expired => const _Ended(
        message: 'La vinculación venció. Genera un QR nuevo en la caja.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular caja')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _step(theme),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ended extends StatelessWidget {
  const _Ended({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Icon(Icons.error_outline, size: 56),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Volver'),
      ),
    ],
  );
}
