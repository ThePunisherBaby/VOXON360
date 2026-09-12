import 'package:flutter/material.dart';
import 'package:voxon_data/voxon_data.dart';

/// Tema Material 3 con el color de la marca del negocio, pensado para pantallas
/// táctiles de caja: botones altos y textos que se leen de lejos.
abstract final class BrandTheme {
  static ThemeData light(Branding branding) =>
      _build(branding, Brightness.light);

  static ThemeData dark(Branding branding) => _build(branding, Brightness.dark);

  static ThemeData _build(Branding branding, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(branding.primaryColorValue),
      brightness: brightness,
    );
    const buttonSize = Size(64, 56);
    const buttonText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return ThemeData(
      colorScheme: scheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          textStyle: buttonText,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
