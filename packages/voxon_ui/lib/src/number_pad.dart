import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Teclado numérico grande para el PIN de un empleado o los códigos de 6 números
/// de la vinculación. También acepta el teclado físico (números, borrar, Enter).
///
/// - Sin [minLength], se envía solo al llegar a [length] dígitos (códigos).
/// - Con [minLength], aparece el botón [submitLabel] desde ese largo (PIN de 4 a 6).
class NumberPad extends StatefulWidget {
  const NumberPad({
    super.key,
    required this.length,
    required this.onCompleted,
    this.minLength,
    this.obscure = false,
    this.busy = false,
    this.errorText,
    this.submitLabel = 'Entrar',
  });

  final int length;
  final int? minLength;

  /// Puntos en vez de números, para el PIN.
  final bool obscure;
  final bool busy;
  final String? errorText;
  final String submitLabel;
  final ValueChanged<String> onCompleted;

  @override
  State<NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<NumberPad> {
  String _digits = '';

  bool get _manualSubmit => widget.minLength != null;

  bool get _canSubmit =>
      !widget.busy && _manualSubmit && _digits.length >= widget.minLength!;

  void _press(String digit) {
    if (widget.busy || _digits.length >= widget.length) return;
    setState(() => _digits += digit);
    if (!_manualSubmit && _digits.length == widget.length) _submit();
  }

  void _erase() {
    if (_digits.isEmpty || widget.busy) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _submit() {
    final value = _digits;
    setState(() => _digits = '');
    widget.onCompleted(value);
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
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        _canSubmit) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _shown {
    if (widget.obscure) return '•' * _digits.length;
    if (_digits.length > 3 && widget.length == 6) {
      return '${_digits.substring(0, 3)} ${_digits.substring(3)}';
    }
    return _digits;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String digit) => OutlinedButton(
      key: Key('pad-$digit'),
      onPressed: widget.busy ? null : () => _press(digit),
      child: Text(digit, style: theme.textTheme.headlineSmall),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              child: Center(
                child: Text(
                  _shown,
                  key: const Key('pad-display'),
                  semanticsLabel: '${_digits.length} de ${widget.length}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    letterSpacing: widget.obscure ? 12 : 4,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 28,
              child: widget.errorText == null
                  ? null
                  : Text(
                      widget.errorText!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
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
                  key: const Key('pad-borrar'),
                  tooltip: 'Borrar',
                  onPressed: widget.busy ? null : _erase,
                  icon: const Icon(Icons.backspace_outlined),
                ),
                key('0'),
                if (_manualSubmit)
                  FilledButton(
                    key: const Key('pad-enviar'),
                    onPressed: _canSubmit ? _submit : null,
                    child: widget.busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.submitLabel),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
