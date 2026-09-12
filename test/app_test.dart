import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/app/app.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/backend/connection_providers.dart';
import 'package:voxon90/core/backend/voxon_client.dart';
import 'package:voxon90/core/core_providers.dart';
import 'package:voxon90/core/storage/key_value_store.dart';
import 'package:voxon90/features/settings/data/settings_repository.dart';

import 'support/fake_voxon_client.dart';

const owner = Employee(id: 'u-owner', name: 'Ana', role: 'owner');
const cashier = Employee(id: 'u-cashier', name: 'Luis', role: 'cashier');
const waiter = Employee(id: 'u-waiter', name: 'Pedro', role: 'waiter');

const savedServer = {'backend.serverUri': 'http://127.0.0.1:8090'};

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeVoxonClient client,
  KeyValueStore? store,
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = const [Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        keyValueStoreProvider.overrideWithValue(
          store ?? InMemoryKeyValueStore(savedServer),
        ),
        voxonClientProvider.overrideWith(
          (ref) => ref.watch(serverUriProvider) == null ? null : client,
        ),
        serverFinderProvider.overrideWithValue(() async => const []),
        serverProbeProvider.overrideWithValue((uri) async {}),
      ],
      child: const VoxonApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.widgetWithText(OutlinedButton, digit));
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
  await tester.pumpAndSettle();
}

FakeVoxonClient staffClient({Map<String, FakeHandler> handlers = const {}}) =>
    FakeVoxonClient(
      pins: const {'1111': owner, '2222': cashier, '3333': waiter},
      handlers: handlers,
    );

void main() {
  testWidgets('sin caja principal pide conectarse y recuerda la dirección', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pumpApp(tester, client: staffClient(), store: store);

    expect(find.text('Conectar con la caja principal'), findsOneWidget);
    expect(
      find.text(
        'No se encontró ninguna caja principal. Revisa que esté encendida y en el mismo WiFi.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '192.168.1.10');
    await tester.tap(find.widgetWithText(FilledButton, 'Conectar'));
    await tester.pumpAndSettle();

    expect(find.text('Entra con tu PIN'), findsOneWidget);
    expect(find.text('Colmado La Esquina'), findsOneWidget);
    expect(store.getString('backend.serverUri'), 'http://192.168.1.10:8090');
  });

  testWidgets('un negocio sin configurar abre la configuración', (
    tester,
  ) async {
    await pumpApp(
      tester,
      client: staffClient(
        handlers: {
          'business.status': (_) => <String, Object?>{
            'configured': false,
            'business': null,
          },
        },
      ),
    );

    expect(find.text('Configura tu negocio'), findsOneWidget);
  });

  testWidgets('un PIN incorrecto muestra el error y no entra', (tester) async {
    await pumpApp(tester, client: staffClient());

    await enterPin(tester, '9999');

    expect(find.text('PIN incorrecto'), findsOneWidget);
    expect(find.text('Entra con tu PIN'), findsOneWidget);
  });

  testWidgets('el dueño entra al resumen con rail lateral en escritorio', (
    tester,
  ) async {
    await pumpApp(tester, client: staffClient());

    await enterPin(tester, '1111');

    expect(find.text('Resumen del 2026-09-11'), findsOneWidget);
    expect(find.text('Presidente 650 ml'), findsOneWidget);
    expect(find.text('RD\$236.00'), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // Un colmado no tiene mesas ni cocina.
    expect(find.text('Mesas'), findsNothing);
  });

  testWidgets('el cajero en teléfono va directo a vender con barra inferior', (
    tester,
  ) async {
    await pumpApp(tester, client: staffClient(), size: const Size(400, 800));

    await enterPin(tester, '2222');

    expect(find.text('No hay productos que coincidan'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Resumen'), findsNothing);
  });

  testWidgets('el mesero de un restaurante abre la orden de una mesa libre', (
    tester,
  ) async {
    final order = <String, Object?>{
      'id': 'o-8',
      'number': 8,
      'kind': 'dine_in',
      'status': 'open',
      'tableId': 't-1',
      'tableName': 'Mesa 1',
      'waiterName': 'Pedro',
      'items': const <Object?>[],
      'estimate': const {
        'subtotalCents': 0,
        'taxCents': 0,
        'tipCents': 0,
        'totalCents': 0,
      },
    };
    final client = staffClient(
      handlers: {
        'business.status': (_) => <String, Object?>{
          'configured': true,
          'business': {'name': 'La Fonda', 'businessType': 'restaurant'},
        },
        'restaurant.tables.list': (_) => [
          <String, Object?>{'id': 't-1', 'name': 'Mesa 1', 'orderId': null},
          <String, Object?>{
            'id': 't-2',
            'name': 'Mesa 2',
            'orderId': 'o-7',
            'orderNumber': 7,
            'waiterName': 'Pedro',
            'itemCount': 3,
            'grossCents': 125000,
          },
        ],
        'restaurant.orders.open': (_) => order,
        'restaurant.orders.get': (_) => order,
      },
    );
    await pumpApp(tester, client: client);

    await enterPin(tester, '3333');

    expect(find.text('Mesa 1'), findsOneWidget);
    expect(find.text('Libre'), findsOneWidget);
    expect(find.text('Orden #7 · Pedro'), findsOneWidget);
    expect(find.text('3 productos · RD\$1,250.00'), findsOneWidget);
    expect(find.text('Cocina'), findsWidgets);

    await tester.tap(find.text('Mesa 1'));
    await tester.pumpAndSettle();

    final open = client.calls.lastWhere(
      (call) => call.$1 == 'restaurant.orders.open',
    );
    expect(open.$2, {'kind': 'dine_in', 'tableId': 't-1'});
    expect(find.text('#8 · Mesa 1'), findsOneWidget);
    expect(find.text('Atiende Pedro'), findsOneWidget);
    expect(find.text('Nada por enviar'), findsOneWidget);
    // El mesero toma la orden pero no cobra.
    expect(find.textContaining('Cobrar cuenta'), findsNothing);
  });

  testWidgets('cambiar el tema en ajustes lo aplica y lo guarda', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore(savedServer);
    await pumpApp(tester, client: staffClient(), store: store);
    await enterPin(tester, '2222');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(SettingsRepository(store).loadThemeMode(), ThemeMode.dark);
  });

  testWidgets('cambiar el idioma traduce la interfaz', (tester) async {
    await pumpApp(tester, client: staffClient());
    await enterPin(tester, '2222');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });

  testWidgets('cerrar sesión vuelve a pedir el PIN', (tester) async {
    await pumpApp(tester, client: staffClient());
    await enterPin(tester, '2222');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Salir'));
    await tester.pumpAndSettle();

    expect(find.text('Entra con tu PIN'), findsOneWidget);
  });

  testWidgets('el dueño vincula la caja con la app del dueño', (tester) async {
    var linked = false;
    Map<String, Object?> cloudStatus() => {
      'configured': true,
      'linked': linked,
      'state': linked ? 'ok' : 'unlinked',
      'lastSyncAt': linked ? '2026-09-11T15:00:00Z' : null,
    };
    final client = staffClient(
      handlers: {
        'cloud.status': (_) => cloudStatus(),
        'cloud.link': (params) {
          linked = params['code'] == 'ABCD-2345';
          return cloudStatus();
        },
      },
    );
    await pumpApp(tester, client: client);
    await enterPin(tester, '1111');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('App del dueño'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Código de vínculo'),
      'ABCD-2345',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
    await tester.pumpAndSettle();

    expect(find.text('Vinculada con la app del dueño'), findsOneWidget);
    expect(find.textContaining('Datos al día'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Desvincular'), findsOneWidget);
  });

  testWidgets('el cajero no ve la app del dueño en ajustes', (tester) async {
    await pumpApp(tester, client: staffClient());
    await enterPin(tester, '2222');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('App del dueño'), findsNothing);
  });
}
