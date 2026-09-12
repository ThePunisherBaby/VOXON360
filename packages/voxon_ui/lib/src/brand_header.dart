import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:voxon_data/voxon_data.dart';

/// Logo y nombre del negocio. Sin logo (o con uno dañado) muestra sus iniciales.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.branding, this.size = 72});

  final Branding branding;
  final double size;

  Uint8List? get _logoBytes {
    final logo = branding.logoDataUrl;
    if (logo == null || !logo.startsWith('data:image/')) return null;
    try {
      return UriData.parse(logo).contentAsBytes();
    } on FormatException {
      return null;
    }
  }

  String get _initials {
    final words = branding.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final letters = words.take(2).map((word) => word[0].toUpperCase()).join();
    return letters.isEmpty ? 'V' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _logoBytes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: SizedBox.square(
            dimension: size,
            child: bytes != null
                ? Image.memory(
                    bytes,
                    key: const Key('logo'),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        _Initials(initials: _initials, size: size),
                  )
                : _Initials(initials: _initials, size: size),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          branding.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primary,
      child: Center(
        child: Text(
          initials,
          key: const Key('iniciales'),
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: size / 2.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
