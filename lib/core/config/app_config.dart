/// Entorno de ejecución, fijado en compilación con
/// `--dart-define-from-file=config/<entorno>.json`.
enum AppEnvironment {
  dev,
  prod;

  static AppEnvironment fromName(String name) =>
      values.firstWhere((env) => env.name == name, orElse: () => dev);
}

/// Configuración inmutable de la app, leída de las variables de compilación.
///
/// Para añadir un valor nuevo (p. ej. la URL de un API), agrégalo a
/// `config/*.json` y léelo aquí con `String.fromEnvironment`.
class AppConfig {
  const AppConfig({required this.environment});

  factory AppConfig.fromEnvironment() => AppConfig(
    environment: AppEnvironment.fromName(
      const String.fromEnvironment('APP_ENV', defaultValue: 'dev'),
    ),
  );

  final AppEnvironment environment;

  bool get isProduction => environment == AppEnvironment.prod;
}
