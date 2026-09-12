import 'package:flutter/material.dart';

/// Tema Material 3 de la app. Cambia [seedColor] para ajustar la marca.
abstract final class AppTheme {
  static const Color seedColor = Color(0xFF4F46E5);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
    );
  }
}
