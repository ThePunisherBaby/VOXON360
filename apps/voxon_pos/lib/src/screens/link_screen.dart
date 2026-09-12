import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon_pos/src/pos_controller.dart';

/// Caja sin vincular: muestra el QR y hace el intercambio de códigos con el celular.
class LinkScreen extends ConsumerStatefulWidget {
  const LinkScreen({super.key});

  @override
  ConsumerState<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends ConsumerState<LinkScreen> {
  PairingTicket? _ticket;
  PairingState? _pairing;
  StreamSubscription<PairingState>? _subscription;
  String? _posCode;
  String? _error;
  bool _busy = false;
  bool _typedCode = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await _subscription?.cancel();
    _subscription = null;
    setState(() {
      _ticket = null;
      _pairing = null;
      _posCode = null;
      _error = null;
    });
    final service = ref.read(deviceLinkServiceProvider);
    try {
      final ticket = await service.startPairing(
        platform: ref.read(platformNameProvider),
      );
      if (!mounted) return;
      setState(() => _ticket = ticket);
      _subscription = service
          .watchPairing(ticket.pairingId)
          .listen(
            (pairing) {
              if (!mounted) return;
              setState(() => _pairing = pairing);
              if (pairing.status == PairingStatus.linked) {
                ref
                    .read(posControllerProvider.notifier)
                    .linkFromPairing(pairing);
              }
            },
            onError: (Object error) {
              if (mounted) setState(() => _error = '$error');
            },
          );
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _confirm(String code) async {
    final ticket = _ticket;
    if (ticket == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final posCode = await ref
          .read(deviceLinkServiceProvider)
          .confirmMobileCode(pairingId: ticket.pairingId, code: code);
      if (mounted) setState(() => _posCode = posCode);
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _step() {
    if (_typedCode) {
      return _TypedCodeForm(onBack: () => setState(() => _typedCode = false));
    }
    final ticket = _ticket;
    if (ticket == null) {
      return _error == null
          ? const _Waiting(text: 'Preparando el código QR…')
          : _Retry(message: _error!, onRetry: _start);
    }
    final pairing = _pairing;
    final posCode = _posCode;
    return switch (pairing?.status ?? PairingStatus.waiting) {
      PairingStatus.waiting => _QrStep(
        ticket: ticket,
        onTypedCode: () => setState(() => _typedCode = true),
      ),
      PairingStatus.claimed || PairingStatus.deviceConfirmed
          when posCode != null =>
        _PosCodeStep(code: posCode),
      PairingStatus.claimed => _MobileCodeStep(
        instanceName: pairing?.instanceName ?? '',
        busy: _busy,
        error: _error,
        onCode: _confirm,
      ),
      PairingStatus.deviceConfirmed => const _Waiting(
        text: 'Esperando que el celular termine la vinculación…',
      ),
      PairingStatus.linked => const _Waiting(
        text: 'Caja vinculada. Abriendo el negocio…',
      ),
      PairingStatus.failed => _Retry(
        message: 'Demasiados códigos incorrectos.',
        onRetry: _start,
      ),
      PairingStatus.cancelled => _Retry(
        message: 'Se canceló la vinculación.',
        onRetry: _start,
      ),
      PairingStatus.expired => _Retry(
        message: 'El código QR venció.',
        onRetry: _start,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandHeader(branding: Branding.voxon, size: 56),
                  const SizedBox(height: 24),
                  _step(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _time(DateTime moment) {
  final local = moment.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _QrStep extends StatelessWidget {
  const _QrStep({required this.ticket, required this.onTypedCode});

  final PairingTicket ticket;
  final VoidCallback onTypedCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('Vincula esta caja', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'En tu celular abre VOXON 360 → Cajas → Vincular con QR y escanea este código.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: QrImageView(
              key: const Key('qr'),
              data: ticket.qr,
              size: 260,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Vence a las ${_time(ticket.expiresAt)}'),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onTypedCode,
          child: const Text('No tengo celular: usar un código de caja'),
        ),
      ],
    );
  }
}

class _MobileCodeStep extends StatelessWidget {
  const _MobileCodeStep({
    required this.instanceName,
    required this.busy,
    required this.error,
    required this.onCode,
  });

  final String instanceName;
  final bool busy;
  final String? error;
  final ValueChanged<String> onCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Vinculando con $instanceName',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Escribe el código de 6 números que muestra el celular.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        NumberPad(length: 6, busy: busy, errorText: error, onCompleted: onCode),
      ],
    );
  }
}

class _PosCodeStep extends StatelessWidget {
  const _PosCodeStep({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CodeDisplay(
          code: code,
          instruction: 'Ahora escribe este código en el celular',
        ),
        const SizedBox(height: 16),
        const Text('La caja queda lista cuando el celular lo confirme.'),
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(text, textAlign: TextAlign.center),
    ],
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Generar un QR nuevo'),
      ),
    ],
  );
}

/// Vinculación con el código de 8 caracteres que genera VOXON 360.
class _TypedCodeForm extends ConsumerStatefulWidget {
  const _TypedCodeForm({required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_TypedCodeForm> createState() => _TypedCodeFormState();
}

class _TypedCodeFormState extends ConsumerState<_TypedCodeForm> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await ref
          .read(deviceLinkServiceProvider)
          .enrollWithCode(
            code: _code.text,
            platform: ref.read(platformNameProvider),
          );
      await ref.read(posControllerProvider.notifier).linkWithDevice(device);
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Código de caja',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'En VOXON 360: Cajas → Agregar con código. Escribe aquí los 8 caracteres.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('codigo-caja'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 9,
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(hintText: 'ABCD-2345', errorText: _error),
          onSubmitted: (_) => _link(),
        ),
        FilledButton(
          onPressed: _busy ? null : _link,
          child: const Text('Vincular'),
        ),
        TextButton(onPressed: widget.onBack, child: const Text('Volver al QR')),
      ],
    );
  }
}
