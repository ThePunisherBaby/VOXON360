import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:voxon90/core/backend/backend_exception.dart';

/// Empleado con sesión abierta.
class Employee {
  const Employee({required this.id, required this.name, required this.role});

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
  );

  final String id;
  final String name;

  /// owner, manager, cashier, waiter o kitchen.
  final String role;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'role': role};
}

/// Cambio hecho desde cualquier equipo del negocio.
class BackendChange {
  const BackendChange({required this.method, this.userId, this.at});

  factory BackendChange.fromJson(Map<String, dynamic> json) => BackendChange(
    method: json['method'] as String,
    userId: json['userId'] as String?,
    at: json['at'] as String?,
  );

  /// Método que causó el cambio, p. ej. `sales.complete`.
  final String method;
  final String? userId;
  final String? at;
}

/// Cliente del servidor local de VOXON90 (backend/server), sin internet.
///
/// Usa `dart:io`, así funciona igual en Android, Windows, macOS y Linux.
class VoxonClient {
  VoxonClient({
    required this.baseUri,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final Duration timeout;
  final HttpClient _http;
  final _sessionExpired = StreamController<void>.broadcast();

  String? _token;
  Employee? _employee;

  String? get token => _token;

  Employee? get employee => _employee;

  bool get isLoggedIn => _token != null;

  /// Emite cuando el servidor rechaza la sesión (vencida o empleado desactivado).
  Stream<void> get sessionExpired => _sessionExpired.stream;

  /// Reutiliza una sesión guardada.
  void restoreSession(String token, Employee employee) {
    _token = token;
    _employee = employee;
  }

  Future<Map<String, dynamic>> health() => _send('GET', '/api/health');

  Future<Employee> login(String pin) async {
    final response = await _send('POST', '/api/login', body: {'pin': pin});
    final result = response['result'] as Map<String, dynamic>;
    _token = result['token'] as String;
    _employee = Employee.fromJson(result['user'] as Map<String, dynamic>);
    return _employee!;
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        await _send('POST', '/api/logout', body: const <String, Object?>{});
      }
    } on BackendException {
      // La sesión local se cierra aunque el servidor no responda.
    } finally {
      _clearSession();
    }
  }

  /// Llama un método del motor y devuelve su resultado.
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final response = await _send(
      'POST',
      '/api/call',
      body: {'method': method, 'params': params},
    );
    return response['result'];
  }

  /// Cambios en vivo (Server-Sent Events). Termina si se corta la conexión.
  Stream<BackendChange> changes() async* {
    final token = _token;
    if (token == null) {
      return;
    }
    final uri = baseUri.replace(
      path: '/api/events',
      queryParameters: {'token': token},
    );
    final HttpClientResponse response;
    try {
      final request = await _http.getUrl(uri).timeout(timeout);
      response = await request.close().timeout(timeout);
    } on Object catch (error) {
      throw _offline(error);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw BackendException(
        'unauthorized',
        'Inicia sesión con tu PIN',
        statusCode: response.statusCode,
      );
    }

    String? event;
    final data = StringBuffer();
    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (event == 'change' && data.isNotEmpty) {
          final decoded = jsonDecode(data.toString());
          if (decoded is Map<String, dynamic>) {
            yield BackendChange.fromJson(decoded);
          }
        }
        event = null;
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
    }
  }

  void close() {
    _sessionExpired.close();
    _http.close(force: true);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final HttpClientResponse response;
    final String text;
    try {
      final request = await _http
          .openUrl(method, baseUri.resolve(path))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (_token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) {
        request.add(utf8.encode(jsonEncode(body)));
      }
      response = await request.close().timeout(timeout);
      text = await response.transform(utf8.decoder).join().timeout(timeout);
    } on Object catch (error) {
      throw _offline(error);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      throw BackendException(
        'invalid_response',
        'El servidor respondió algo inesperado',
        statusCode: response.statusCode,
      );
    }
    if (decoded['ok'] == false) {
      final error = decoded['error'];
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      if (response.statusCode == HttpStatus.unauthorized &&
          path != '/api/login') {
        _clearSession();
        _sessionExpired.add(null);
      }
      throw BackendException(
        code ?? 'internal_error',
        message ?? 'Error desconocido',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  BackendException _offline(Object error) {
    if (error is BackendException) return error;
    return BackendException(
      BackendException.offline,
      error is TimeoutException
          ? 'La caja principal no responde'
          : 'No hay conexión con la caja principal. Revisa el WiFi del negocio.',
    );
  }

  void _clearSession() {
    _token = null;
    _employee = null;
  }
}
