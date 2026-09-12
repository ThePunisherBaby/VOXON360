import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/core_providers.dart';
import 'package:voxon90/features/settings/data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(keyValueStoreProvider)),
);

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

final localeProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);

/// Tema elegido por el usuario (sistema, claro u oscuro).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(settingsRepositoryProvider).loadThemeMode();

  Future<void> setThemeMode(ThemeMode mode) {
    state = mode;
    return ref.read(settingsRepositoryProvider).saveThemeMode(mode);
  }
}

/// Idioma elegido por el usuario; `null` sigue el idioma del sistema.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => ref.watch(settingsRepositoryProvider).loadLocale();

  Future<void> setLocale(Locale? locale) {
    state = locale;
    return ref.read(settingsRepositoryProvider).saveLocale(locale);
  }
}
