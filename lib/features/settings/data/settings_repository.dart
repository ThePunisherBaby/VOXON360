import 'package:flutter/material.dart';

import 'package:voxon90/core/storage/key_value_store.dart';

/// Lee y guarda los ajustes del usuario.
class SettingsRepository {
  const SettingsRepository(this._store);

  static const _themeModeKey = 'settings.themeMode';
  static const _localeKey = 'settings.locale';

  final KeyValueStore _store;

  ThemeMode loadThemeMode() {
    final name = _store.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _store.setString(_themeModeKey, mode.name);

  /// Devuelve `null` cuando se usa el idioma del sistema.
  Locale? loadLocale() {
    final code = _store.getString(_localeKey);
    return code == null ? null : Locale(code);
  }

  Future<void> saveLocale(Locale? locale) => locale == null
      ? _store.remove(_localeKey)
      : _store.setString(_localeKey, locale.languageCode);
}
