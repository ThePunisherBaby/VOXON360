import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon_pos/src/app.dart';
import 'package:voxon_pos/src/link_store.dart';
import 'package:voxon_pos/src/pos_controller.dart';

import 'support/fakes.dart';

typedef Fakes = ({
  FakeDeviceLinkService link,
  FakePosSessionService session,
  MemoryLinkStore store,
});

const linkedColmado = LinkedInstance(
  instanceId: 'i1',
  instanceName: 'Colmado Don Pedro',
  deviceName: 'Caja 1',
  deviceNumber: 1,
);

Future<Fakes> pumpPos(
  WidgetTester tester, {
  LinkedInstance? linked,
  void Function(FakePosSessionService session)? configure,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fakes = (
    link: FakeDeviceLinkService(),
    session: FakePosSessionService(),
    store: MemoryLinkStore(linked),
  );
  configure?.call(fakes.session);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        deviceLinkServiceProvider.overrideWithValue(fakes.link),
        posSessionServiceProvider.overrideWithValue(fakes.session),
        linkStoreProvider.overrideWithValue(fakes.store),
        platformNameProvider.overrideWithValue('windows'),
      ],
      child: const PosApp(),
    ),
  );
  await settle(tester);
  return fakes;
}

/// Unos cuadros para que corran las tareas pendientes; sin pumpAndSettle,
/// porque los indicadores de progreso nunca terminan de animar.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
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

void main() {
  testWidgets(
    'una caja nueva se vincula con QR y doble código y toma la marca del negocio',
    (tester) async {
      final fakes = await pumpPos(tester);

      expect(find.text('Vincula esta caja'), findsOneWidget);
      expect(find.byKey(const Key('qr')), findsOneWidget);
      expect(fakes.link.platforms, ['windows']);

      // El dueño escaneó el QR con VOXON 360.
      fakes.link.pairing.add(
        const PairingState(
          id: 'p1',
          status: PairingStatus.claimed,
          instanceId: 'i1',
          instanceName: 'Colmado Don Pedro',
        ),
      );
      await settle(tester);
      expect(find.text('Vinculando con Colmado Don Pedro'), findsOneWidget);

      await tapDigits(tester, '111111');
      expect(find.text('Código incorrecto'), findsOneWidget);

      await tapDigits(tester, '482913');
      expect(find.text('175 204'), findsOneWidget);
      expect(
        find.text('Ahora escribe este código en el celular'),
        findsOneWidget,
      );

      // El dueño escribió el código de la caja en el celular.
      fakes.link.pairing.add(
        const PairingState(
          id: 'p1',
          status: PairingStatus.linked,
          instanceId: 'i1',
          instanceName: 'Colmado Don Pedro',
          deviceName: 'Caja mostrador',
          deviceNumber: 1,
        ),
      );
      await settle(tester);

      expect(fakes.store.link?.instanceId, 'i1');
      expect(find.text('Colmado Don Pedro'), findsOneWidget);
      expect(find.text('Caja mostrador · caja 1'), findsOneWidget);
      expect(find.text('Toca tu nombre'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Colmado Don Pedro',
      );
    },
  );

  testWidgets('el empleado entra con su PIN y al salir la caja se bloquea', (
    tester,
  ) async {
    final fakes = await pumpPos(tester, linked: linkedColmado);

    await tester.tap(find.text('Luis Pérez'));
    await settle(tester);
    expect(find.text('Hola, Luis Pérez'), findsOneWidget);

    await tapDigits(tester, '1111');
    await tester.tap(find.byKey(const Key('pad-enviar')));
    await settle(tester);
    expect(find.text('PIN incorrecto'), findsOneWidget);

    await tapDigits(tester, '2468');
    await tester.tap(find.byKey(const Key('pad-enviar')));
    await settle(tester);

    expect(find.text('Luis Pérez · Cajero'), findsOneWidget);
    expect(find.text('Caja lista para vender'), findsOneWidget);
    expect(find.text('Colmado o minimercado'), findsOneWidget);

    await tester.tap(find.byTooltip('Salir'));
    await settle(tester);
    expect(find.text('Toca tu nombre'), findsOneWidget);
    expect(fakes.session.logouts, ['i1']);
  });

  testWidgets('sin celular, la caja se vincula con el código escrito', (
    tester,
  ) async {
    final fakes = await pumpPos(tester);
    fakes.link.enrollResult = const LinkedDevice(
      instanceId: 'i2',
      instanceName: 'La Fonda',
      mode: 'restaurant',
      deviceName: 'Caja bar',
      deviceNumber: 2,
    );

    await tester.tap(find.text('No tengo celular: usar un código de caja'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('codigo-caja')), 'abcd-2345');
    await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
    await settle(tester);

    expect(fakes.link.enrolledCode, 'abcd-2345');
    expect(fakes.store.link?.instanceName, 'La Fonda');
    expect(find.text('Toca tu nombre'), findsOneWidget);
  });

  testWidgets('si el dueño desactivó la caja, ofrece vincularla de nuevo', (
    tester,
  ) async {
    final fakes = await pumpPos(
      tester,
      linked: linkedColmado,
      configure: (session) => session.revoked = true,
    );

    expect(find.textContaining('vincúlala de nuevo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Vincular de nuevo'));
    await settle(tester);

    expect(fakes.store.link, isNull);
    expect(find.text('Vincula esta caja'), findsOneWidget);
  });
}
