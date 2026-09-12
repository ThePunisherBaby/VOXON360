import 'dart:async';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/voxon_client.dart';

typedef FakeHandler = Object? Function(Map<String, Object?> params);

const colmadoStatus = <String, Object?>{
  'configured': true,
  'business': {'name': 'Colmado La Esquina', 'businessType': 'colmado'},
};

/// Respuestas mínimas para que cada sección cargue sin datos.
final defaultHandlers = <String, FakeHandler>{
  'business.status': (_) => colmadoStatus,
  'catalog.products.list': (_) => const <Object?>[],
  'cash.current': (_) => null,
  'reports.dashboard': (_) => <String, Object?>{
    'day': '2026-09-11',
    'sales': <String, Object?>{
      'count': 2,
      'totalCents': 23600,
      'taxCents': 3600,
      'tipCents': 0,
      'discountCents': 0,
      'averageTicketCents': 11800,
    },
    'payments': [
      <String, Object?>{'method': 'cash', 'amountCents': 23600},
    ],
    'topProducts': [
      <String, Object?>{
        'productId': 'p-1',
        'description': 'Presidente 650 ml',
        'quantityMilli': 2000,
        'netCents': 20000,
      },
    ],
    'voidedSales': 0,
    'openCashSession': null,
    'lowStockCount': 0,
    'receivablesCents': 0,
    'openOrders': 0,
  },
  'inventory.lowStock': (_) => const <Object?>[],
  'reports.receivables': (_) => <String, Object?>{
    'customers': const <Object?>[],
    'totalCents': 0,
  },
  'restaurant.tables.list': (_) => const <Object?>[],
  'restaurant.orders.list': (_) => const <Object?>[],
  'restaurant.kitchen.queue': (_) => const <Object?>[],
  'cloud.status': (_) => const <String, Object?>{
    'configured': false,
    'linked': false,
  },
};

/// Cliente sin red que responde con datos preparados por cada prueba.
class FakeVoxonClient extends VoxonClient {
  FakeVoxonClient({
    this.pins = const {},
    Map<String, FakeHandler> handlers = const {},
  }) : handlers = {...defaultHandlers, ...handlers},
       super(baseUri: Uri.parse('http://127.0.0.1:8090'));

  /// PIN → empleado que entra con él.
  final Map<String, Employee> pins;
  final Map<String, FakeHandler> handlers;

  /// Métodos llamados, en orden, con sus parámetros.
  final calls = <(String, Map<String, Object?>)>[];

  final _changes = StreamController<BackendChange>.broadcast();
  Employee? _signedIn;

  @override
  Employee? get employee => _signedIn;

  @override
  bool get isLoggedIn => _signedIn != null;

  @override
  Future<Map<String, dynamic>> health() async => {'ok': true};

  @override
  Future<Employee> login(String pin) async {
    final employee = pins[pin];
    if (employee == null) {
      throw const BackendException(
        'invalid_pin',
        'PIN incorrecto',
        statusCode: 401,
      );
    }
    return _signedIn = employee;
  }

  @override
  Future<void> logout() async {
    _signedIn = null;
  }

  @override
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    final handler = handlers[method];
    if (handler == null) {
      throw BackendException('not_found', 'Sin respuesta de prueba: $method');
    }
    return handler(params);
  }

  @override
  Stream<BackendChange> changes() => _changes.stream;

  /// Simula un cambio hecho desde otro equipo.
  void emitChange(String method) => _changes.add(BackendChange(method: method));
}
