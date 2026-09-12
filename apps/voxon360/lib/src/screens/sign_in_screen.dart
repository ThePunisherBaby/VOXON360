import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon360/src/providers.dart';

/// Entrada del dueño o administrador con su correo.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(
        () =>
            _error = 'Escribe tu correo y una contraseña de 6 o más caracteres',
      );
      return;
    }
    final auth = ref.read(accountAuthServiceProvider);
    await _run(
      () => _creating
          ? auth.registerWithEmail(email, password)
          : auth.signInWithEmail(email, password),
    );
  }

  Future<void> _google() =>
      _run(() => ref.read(accountAuthServiceProvider).signInWithGoogle());

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandHeader(
                    branding: Branding(
                      displayName: 'VOXON 360',
                      primaryColorHex: '#1B5E20',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Administra tus negocios y tus cajas',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Correo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_creating ? 'Crear cuenta' : 'Entrar'),
                  ),
                  if (ref.watch(accountAuthServiceProvider).canUseGoogle) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Entrar con Google'),
                    ),
                  ],
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                          }),
                    child: Text(
                      _creating ? 'Ya tengo cuenta' : 'Crear una cuenta nueva',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
