import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/config/app_config.dart';
import 'package:voxon90/core/storage/key_value_store.dart';

/// Configuración de la app según el entorno de compilación.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Almacenamiento de ajustes de este equipo. Su creación es asíncrona, así que
/// se inicializa en `bootstrap()` y se inyecta con `overrideWithValue`.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError(
    'keyValueStoreProvider debe sobrescribirse en bootstrap() o en el test.',
  ),
);
