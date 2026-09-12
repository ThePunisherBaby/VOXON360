import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Logger central de la app.
///
/// Todo el código registra a través de esta clase, así más adelante se puede
/// enviar a un servicio remoto (Sentry, Crashlytics...) cambiando un solo sitio.
abstract final class AppLogger {
  static void debug(String message) => _log(message, level: 500);

  static void info(String message) => _log(message, level: 800);

  static void warning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _log(message, level: 900, error: error, stackTrace: stackTrace);

  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(message, level: 1000, error: error, stackTrace: stackTrace);

  static void _log(
    String message, {
    required int level,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // En release solo se conservan advertencias y errores.
    if (kReleaseMode && level < 900) return;
    developer.log(
      message,
      name: 'voxon90',
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
