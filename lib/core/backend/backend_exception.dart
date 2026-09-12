/// Error del backend local, con el mismo código estable que devuelve el motor
/// (`cash_session_closed`, `credit_limit_exceeded`, `unauthorized`...).
class BackendException implements Exception {
  const BackendException(this.code, this.message, {this.statusCode});

  /// Sin conexión con la caja principal.
  static const offline = 'offline';

  final String code;
  final String message;
  final int? statusCode;

  bool get isOffline => code == offline;

  bool get isUnauthorized => code == 'unauthorized';

  @override
  String toString() => message;
}
