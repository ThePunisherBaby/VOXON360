import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon360/src/app.dart';
import 'package:voxon360/src/providers.dart';
import 'package:voxon360/src/screens/pairing_flow_screen.dart';

import 'support/fakes.dart';

typedef Fakes = ({FakeAccountAuthService auth, FakeAdminService admin});

const laFonda = MyInstance(
  id: 'i1',
  accountId: 'c1',
  name: 'La Fonda',
  mode: 'restaurant',
  role: StaffRole.owner,
);

void useLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<Fakes> pumpApp(
  WidgetTester tester, {
  String? uid,
  List<MyInstance> instances = const [],
  bool google = false,
}) async {
  useLargeScreen(tester);
  final fakes = (
    auth: FakeAccountAuthService(currentUserId: uid, canUseGoogle: google),
    admin: FakeAdminService()..instances = instances,
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        accountAuthServiceProvider.overrideWithValue(fakes.auth),
        adminServiceProvider.overrideWithValue(fakes.admin),
        canScanProvider.overrideWithValue(false),
      ],
      child: const Voxon360App(),
    ),
  );
  await settle(tester);
  return fakes;
}

/// Unos cuadros para que corran las tareas pendientes; sin pumpAndSettle,
/// porque los indicadores de progreso nunca terminan de animar.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('pad-$digit')));
    await tester.pump();
  }
  await settle(tester);
}

VoidCallback? onPressedOf(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed;

void main() {
  testWidgets('el dueño entra, elige restaurante y crea su negocio', (
    tester,
  ) async {
    final fakes = await pumpApp(tester);

    expect(find.text('Administra tus negocios y tus cajas'), findsOneWidget);
    expect(find.text('Entrar con Google'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'dueno@ejemplo.com');
    await tester.enterText(find.byType(TextField).at(1), 'otra-clave');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await settle(tester);
    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'secreto1');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await settle(tester);

    // Paso 1: los modos que todavía no están listos no se pueden elegir.
    expect(find.text('¿Qué tipo de negocio tienes?'), findsOneWidget);
    expect(find.text('Pronto'), findsNWidgets(16));
    await tester.tap(find.byKey(const Key('modo-bar')));
    await settle(tester);
    expect(onPressedOf(tester, const Key('siguiente')), isNull);

    await tester.tap(find.byKey(const Key('modo-restaurant')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('siguiente')));
    await settle(tester);

    // Paso 2: sin nombre no se puede seguir.
    expect(find.text('Datos de tu negocio'), findsOneWidget);
    expect(onPressedOf(tester, const Key('siguiente')), isNull);
    await tester.enterText(find.byKey(const Key('nombre-negocio')), 'La Fonda');
    await settle(tester);
    await tester.tap(find.byKey(const Key('siguiente')));
    await settle(tester);

    // Paso 3: vista previa con las reglas del restaurante y la prueba gratis.
    expect(find.text('Así queda tu negocio'), findsOneWidget);
    expect(find.textContaining('propina legal del 10 %'), findsOneWidget);
    expect(find.textContaining('Prueba gratis de 14 días'), findsOneWidget);

    await tester.tap(find.byKey(const Key('siguiente')));
    await settle(tester);

    expect(fakes.admin.created, [
      (accountName: 'La Fonda', instanceName: 'La Fonda', mode: 'restaurant'),
    ]);
    expect(find.text('Tu puesto: Dueño'), findsOneWidget);
    expect(find.text('Vincular una caja'), findsOneWidget);
  });

  testWidgets('en el celular se puede entrar con Google y salir', (
    tester,
  ) async {
    final fakes = await pumpApp(
      tester,
      instances: const [laFonda],
      google: true,
    );

    await tester.tap(find.text('Entrar con Google'));
    await settle(tester);
    expect(fakes.auth.currentUserId, 'dueno');
    expect(find.text('Tu puesto: Dueño'), findsOneWidget);

    await tester.tap(find.byTooltip('Cuenta'));
    await settle(tester);
    await tester.tap(find.text('Cerrar sesión'));
    await settle(tester);
    expect(find.text('Administra tus negocios y tus cajas'), findsOneWidget);
  });

  testWidgets(
    'vincular con QR: el celular da su código y escribe el de la caja',
    (tester) async {
      useLargeScreen(tester);
      final admin = FakeAdminService();
      final qr = PairingQr.tryParse(
        'voxon://pair?p=Ab3xY9kLmN0pQrStUvWx&t=k8J2-mZ_q0aB7cD9eF1gH3iJ5kL7mN9oP1qR3sT5uV7',
      )!;
      await tester.pumpWidget(
        ProviderScope(
          retry: (retryCount, error) => null,
          overrides: [adminServiceProvider.overrideWithValue(admin)],
          child: MaterialApp(
            home: PairingFlowScreen(instanceId: 'i1', qr: qr),
          ),
        ),
      );
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('nombre-caja-qr')),
        'Caja bar',
      );
      await tester.tap(find.text('Reservar la caja'));
      await settle(tester);
      expect(admin.claimedNames, ['Caja bar']);
      expect(find.text('Escribe este código en la caja'), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);

      // La caja escribió el código del celular y ahora muestra el suyo.
      admin.pairing.add(
        const PairingState(id: 'p1', status: PairingStatus.deviceConfirmed),
      );
      await settle(tester);
      expect(
        find.text('Escribe el código que ahora muestra la caja'),
        findsOneWidget,
      );

      await tapDigits(tester, '111111');
      expect(find.text('Código incorrecto'), findsOneWidget);

      await tapDigits(tester, '175204');
      expect(find.text('Caja vinculada'), findsOneWidget);
      expect(find.text('Caja bar · caja 1'), findsOneWidget);
    },
  );

  testWidgets(
    'cajas: código escrito, aviso del QR en la computadora y desactivar',
    (tester) async {
      final fakes = await pumpApp(
        tester,
        uid: 'dueno',
        instances: const [laFonda],
      );

      await tester.tap(find.text('Vincular una caja'));
      await settle(tester);
      expect(find.text('Caja 1 · vinculada con QR'), findsOneWidget);

      await tester.tap(find.text('Vincular con QR'));
      await settle(tester);
      expect(find.text('Escanear desde el celular'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await settle(tester);

      await tester.tap(find.text('Agregar con código'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('nombre-caja')), 'Caja bar');
      await tester.tap(find.text('Crear código'));
      await settle(tester);
      expect(find.text('Código para Caja bar'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('codigo-caja')))
            .data,
        'ABCD-2345',
      );
      await tester.tap(find.text('Listo'));
      await settle(tester);

      await tester.tap(find.byTooltip('Desactivar'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await settle(tester);
      expect(fakes.admin.revoked, ['d1']);
      expect(
        find.text('Caja 1 · vinculada con QR · desactivada'),
        findsOneWidget,
      );
    },
  );

  testWidgets('empleados: se agregan con puesto y PIN de 4 a 6 números', (
    tester,
  ) async {
    final fakes = await pumpApp(
      tester,
      uid: 'dueno',
      instances: const [laFonda],
    );

    await tester.tap(find.text('Agregar empleados con PIN'));
    await settle(tester);
    expect(find.text('Todavía no hay empleados.'), findsOneWidget);

    await tester.tap(find.text('Agregar empleado'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('empleado-nombre')),
      'Ana Gómez',
    );
    await tester.enterText(find.byKey(const Key('empleado-pin')), '12');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(find.text('El PIN tiene de 4 a 6 números'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('empleado-pin')), '2468');
    await tester.tap(find.text('Guardar'));
    await settle(tester);

    expect(fakes.admin.savedPins, {'s1': '2468'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.widgetWithText(ListTile, 'Ana Gómez'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Cajero'), findsOneWidget);
  });
}
