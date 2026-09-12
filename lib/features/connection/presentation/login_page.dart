import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Ingreso con PIN: teclado grande para pantallas táctiles y teclado físico.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String _pin = '';
  String? _error;
  bool _sending = false;

  void _press(String digit) {
    if (_pin.length < 6 && !_sending) {
      setState(() {
        _pin += digit;
        _error = null;
      });
    }
  }

  void _erase() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_pin.length < 4) {
      setState(() => _error = AppLocalizations.of(context).loginPinLength);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(sessionProvider.notifier).login(_pin);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _pin = '';
          _sending = false;
        });
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final character = event.character;
    if (character != null && RegExp(r'^\d$').hasMatch(character)) {
      _press(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _erase();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final businessName = ref.watch(businessStatusProvider).value?.name;

    Widget key(String digit) => OutlinedButton(
      onPressed: () => _press(digit),
      child: Text(digit, style: theme.textTheme.headlineSmall),
    );

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      businessName ?? l10n.appTitle,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.loginTitle),
                    SizedBox(
                      height: 56,
                      child: Center(
                        child: Text(
                          '•' * _pin.length,
                          semanticsLabel: '${_pin.length}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            letterSpacing: 12,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: _error == null
                          ? null
                          : Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                    ),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        for (final digit in [
                          '1',
                          '2',
                          '3',
                          '4',
                          '5',
                          '6',
                          '7',
                          '8',
                          '9',
                        ])
                          key(digit),
                        IconButton.outlined(
                          tooltip: l10n.loginDelete,
                          onPressed: _erase,
                          icon: const Icon(Icons.backspace_outlined),
                        ),
                        key('0'),
                        FilledButton(
                          onPressed: _sending ? null : _submit,
                          child: Text(l10n.loginAction),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          ref.read(serverUriProvider.notifier).forget(),
                      child: Text(l10n.loginChangeServer),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
