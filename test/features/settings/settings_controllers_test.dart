import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/core/core_providers.dart';
import 'package:voxon90/core/storage/key_value_store.dart';
import 'package:voxon90/features/settings/application/settings_controllers.dart';

void main() {
  late InMemoryKeyValueStore store;

  /// Un contenedor nuevo sobre el mismo [store] simula reabrir la app.
  ProviderContainer openApp() => ProviderContainer.test(
    overrides: [keyValueStoreProvider.overrideWithValue(store)],
  );

  setUp(() => store = InMemoryKeyValueStore());

  test('por defecto sigue el tema y el idioma del sistema', () {
    final container = openApp();

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(localeProvider), isNull);
  });

  test('el tema elegido se conserva al reabrir', () async {
    await openApp()
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(openApp().read(themeModeProvider), ThemeMode.dark);
  });

  test('el idioma elegido se conserva y "sistema" lo borra', () async {
    final controller = openApp().read(localeProvider.notifier);

    await controller.setLocale(const Locale('en'));
    expect(openApp().read(localeProvider), const Locale('en'));

    await controller.setLocale(null);
    expect(openApp().read(localeProvider), isNull);
  });
}
