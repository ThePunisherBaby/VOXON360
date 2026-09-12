import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/app/app.dart';
import 'package:voxon90/core/config/app_config.dart';
import 'package:voxon90/core/core_providers.dart';
import 'package:voxon90/core/logging/app_logger.dart';
import 'package:voxon90/core/storage/key_value_store.dart';
import 'package:voxon90/core/storage/shared_preferences_store.dart';

/// Inicializa los servicios y arranca la app. Los datos del negocio viven en
/// el backend local (caja principal); aquí solo se guardan ajustes del equipo.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppLogger.error('Error de Flutter', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error('Error no capturado', error, stackTrace);
    return true;
  };

  final config = AppConfig.fromEnvironment();
  AppLogger.info('Iniciando VOXON90 (${config.environment.name})');

  KeyValueStore store;
  try {
    store = await SharedPreferencesStore.create();
  } catch (error, stackTrace) {
    // Un archivo de ajustes dañado no debe impedir que la app abra.
    AppLogger.error('No se pudieron cargar los ajustes', error, stackTrace);
    store = InMemoryKeyValueStore();
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        keyValueStoreProvider.overrideWithValue(store),
      ],
      child: const VoxonApp(),
    ),
  );
}
