import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90_owner/app.dart';
import 'package:voxon90_owner/providers.dart';

import 'support/fake_owner_repository.dart';

Future<FakeOwnerRepository> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = FakeOwnerRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ownerRepositoryProvider.overrideWithValue(repository)],
      child: const OwnerApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Correo'),
    'ana@correo.com',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Contraseña'),
    'secreta1',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin sesión pide el correo', (tester) async {
    await pumpApp(tester);

    expect(find.text('VOXON90 Dueño'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  testWidgets('una contraseña corta no intenta entrar', (tester) async {
    await pumpApp(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Correo'),
      'ana@correo.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Contraseña'), '123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('6 o más caracteres'), findsOneWidget);
  });

  testWidgets('el dueño entra, elige su negocio y ve el día', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    expect(find.text('Tus negocios'), findsOneWidget);
    await tester.tap(find.text('Colmado La Esquina'));
    await tester.pumpAndSettle();

    expect(find.text('Ventas de hoy'), findsOneWidget);
    expect(find.text(r'RD$236.00'), findsOneWidget);
    expect(find.text('2 ventas · ITBIS RD\$36.00'), findsOneWidget);
    expect(find.text('Actualizado 15:04'), findsOneWidget);
    expect(find.text('En caja RD\$1,118.00'), findsOneWidget);
    expect(find.text('Presidente 650 ml'), findsOneWidget);
    expect(find.text('Fiao RD\$59.00'), findsOneWidget);
  });

  testWidgets('lo que necesita atención está separado', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Colmado La Esquina'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Atención'));
    await tester.pumpAndSettle();

    expect(find.text('Refresco'), findsOneWidget);
    expect(find.text('Quedan 3'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);
    expect(find.text('Abierta por Luis'), findsOneWidget);
  });

  testWidgets('genera un código para vincular la caja y quita una vinculada', (
    tester,
  ) async {
    final repository = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Colmado La Esquina'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cajas'));
    await tester.pumpAndSettle();
    expect(find.text('Caja principal'), findsOneWidget);

    await tester.tap(find.text('Vincular una caja'));
    await tester.pump();

    expect(repository.createdCodes, ['ABCD2345']);
    expect(find.text('ABCD-2345'), findsOneWidget);
    expect(find.textContaining('Vence en'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar'));
    await tester.pump();

    expect(find.text('Caja principal'), findsNothing);
    expect(
      find.text('Ninguna caja está enviando datos todavía'),
      findsOneWidget,
    );
  });
}
