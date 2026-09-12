import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/voxon_client.dart';

/// Servidor HTTP local que imita al servidor Java para probar el cliente.
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final requests = <({String path, String? authorization, Object? body})>[];
  late Future<void> Function(HttpRequest request, Object? body) handler;

  static Future<FakeServer> start() async {
    final server = FakeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._handle);
    return server;
  }

  Uri get uri => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final body = text.isEmpty ? null : jsonDecode(text);
    requests.add((
      path: request.uri.path,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      body: body,
    ));
    await handler(request, body);
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> reply(HttpRequest request, int status, Object body) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

const loginBody = {
  'ok': true,
  'result': {
    'token': 't-1',
    'user': {'id': 'u-1', 'name': 'Ana', 'role': 'owner'},
  },
};

void main() {
  late FakeServer server;
  late VoxonClient client;

  setUp(() async {
    server = await FakeServer.start();
    client = VoxonClient(
      baseUri: server.uri,
      timeout: const Duration(seconds: 3),
    );
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  test('el login guarda la sesión y call envía el token', () async {
    server.handler = (request, body) => request.uri.path == '/api/login'
        ? reply(request, 200, loginBody)
        : reply(request, 200, {
            'ok': true,
            'result': [
              {'id': 'u-1'},
            ],
          });

    final employee = await client.login('1111');
    final users = await client.call('users.list');

    expect(employee.name, 'Ana');
    expect(client.isLoggedIn, isTrue);
    expect(users, [
      {'id': 'u-1'},
    ]);
    expect(server.requests[1].authorization, 'Bearer t-1');
    expect(server.requests[1].body, {
      'method': 'users.list',
      'params': <String, Object?>{},
    });
  });

  test('los errores del motor conservan su código', () async {
    server.handler = (request, body) => reply(request, 409, {
      'ok': false,
      'error': {
        'code': 'cash_session_closed',
        'message': 'No hay una caja abierta',
      },
    });

    await expectLater(
      client.call('cash.movement'),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', 'cash_session_closed')
            .having((error) => error.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('un 401 cierra la sesión y avisa; un PIN incorrecto no', () async {
    var expired = 0;
    final subscription = client.sessionExpired.listen((_) => expired++);
    server.handler = (request, body) async {
      if (request.uri.path == '/api/login' && (body as Map)['pin'] == '9999') {
        return reply(request, 401, {
          'ok': false,
          'error': {'code': 'unauthorized', 'message': 'PIN incorrecto'},
        });
      }
      if (request.uri.path == '/api/login') {
        return reply(request, 200, loginBody);
      }
      return reply(request, 401, {
        'ok': false,
        'error': {'code': 'unauthorized', 'message': 'Inicia sesión'},
      });
    };

    await expectLater(client.login('9999'), throwsA(isA<BackendException>()));
    await client.login('1111');
    await expectLater(
      client.call('users.list'),
      throwsA(isA<BackendException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.isLoggedIn, isFalse);
    expect(expired, 1);
    await subscription.cancel();
  });

  test('sin servidor da un error de conexión claro', () async {
    await server.close();
    await expectLater(
      client.health(),
      throwsA(
        isA<BackendException>().having(
          (error) => error.isOffline,
          'offline',
          isTrue,
        ),
      ),
    );
  });

  test('recibe los cambios en vivo', () async {
    server.handler = (request, body) async {
      if (request.uri.path == '/api/login') {
        return reply(request, 200, loginBody);
      }
      expect(request.uri.queryParameters['token'], 't-1');
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response
        ..write(': conectado\n\n')
        ..write('event: change\n')
        ..write('data: {"method":"sales.complete","userId":"u-1"}\n\n');
      await request.response.close();
    };
    await client.login('1111');

    final changes = await client.changes().toList();

    expect(changes.single.method, 'sales.complete');
    expect(changes.single.userId, 'u-1');
  });
}
