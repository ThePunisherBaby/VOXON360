import 'package:flutter/material.dart';
import 'package:voxon_data/voxon_data.dart';

/// Código de 6 números en grande, para dictarlo o escribirlo en el otro equipo.
class CodeDisplay extends StatelessWidget {
  const CodeDisplay({super.key, required this.code, required this.instruction});

  final String code;

  /// Qué hacer con el código, p. ej. «Escribe este código en la caja».
  final String instruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              instruction,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(
              formatPairingCode(code),
              key: const Key('codigo'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
