import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BrandTheme.light(Branding.voxon),
      home: Scaffold(
        body: Center(child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('pad-$digit')));
    await tester.pump();
  }
}

void main() {
  group('teclado numérico', () {
    testWidgets('un código de 6 números se envía solo al completarse', (
      tester,
    ) async {
      final sent = <String>[];
      await pump(tester, NumberPad(length: 6, onCompleted: sent.add));

      await tapDigits(tester, '4827');
      expect(find.text('482 7'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pad-borrar')));
      await tester.pump();
      expect(find.text('482'), findsOneWidget);
      await tapDigits(tester, '91');
      expect(sent, isEmpty, reason: 'con 5 números todavía no se envía');
      await tapDigits(tester, '3');

      expect(sent, ['482913']);
      expect(find.byKey(const Key('pad-enviar')), findsNothing);
    });

    testWidgets('el PIN se oculta y se envía con el botón desde 4 números', (
      tester,
    ) async {
      final sent = <String>[];
      await pump(
        tester,
        NumberPad(
          length: 6,
          minLength: 4,
          obscure: true,
          onCompleted: sent.add,
        ),
      );

      await tapDigits(tester, '246');
      expect(find.text('•••'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pad-enviar')))
            .onPressed,
        isNull,
      );
      await tapDigits(tester, '8');
      await tester.tap(find.byKey(const Key('pad-enviar')));
      await tester.pump();

      expect(sent, ['2468']);
      expect(find.text('••••'), findsNothing);
    });

    testWidgets('acepta el teclado físico', (tester) async {
      final sent = <String>[];
      await pump(
        tester,
        NumberPad(
          length: 6,
          minLength: 4,
          obscure: true,
          onCompleted: sent.add,
        ),
      );

      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }

      expect(sent, ['1357']);
    });

    testWidgets('muestra el error y no escribe mientras espera', (
      tester,
    ) async {
      final sent = <String>[];
      await pump(
        tester,
        NumberPad(
          length: 6,
          busy: true,
          errorText: 'Código incorrecto',
          onCompleted: sent.add,
        ),
      );

      expect(find.text('Código incorrecto'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pad-1')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('pad-display'))).data,
        '',
      );
    });
  });

  group('marca del negocio', () {
    test('el tema toma el color de la marca', () {
      final red = BrandTheme.light(
        const Branding(displayName: 'La Fonda', primaryColorHex: '#C62828'),
      );
      final green = BrandTheme.light(Branding.voxon);
      expect(red.colorScheme.primary, isNot(green.colorScheme.primary));
      expect(
        BrandTheme.dark(Branding.voxon).colorScheme.brightness,
        Brightness.dark,
      );
    });

    testWidgets('sin logo muestra las iniciales del negocio', (tester) async {
      await pump(
        tester,
        const BrandHeader(
          branding: Branding(
            displayName: 'Colmado Don Pedro',
            primaryColorHex: '#EF6C00',
          ),
        ),
      );
      expect(find.text('Colmado Don Pedro'), findsOneWidget);
      expect(find.text('CD'), findsOneWidget);
      expect(find.byKey(const Key('logo')), findsNothing);
    });

    testWidgets('con logo lo muestra en vez de las iniciales', (tester) async {
      // PNG de 1×1 píxel.
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      await pump(
        tester,
        BrandHeader(
          branding: Branding(
            displayName: 'La Fonda',
            primaryColorHex: '#C62828',
            logoDataUrl: 'data:image/png;base64,${base64.normalize(png)}',
          ),
        ),
      );
      expect(find.byKey(const Key('logo')), findsOneWidget);
    });

    testWidgets('el código se muestra en dos grupos', (tester) async {
      await pump(
        tester,
        const CodeDisplay(
          code: '482913',
          instruction: 'Escribe este código en la caja',
        ),
      );
      expect(find.text('482 913'), findsOneWidget);
      expect(find.text('Escribe este código en la caja'), findsOneWidget);
    });
  });

  testWidgets('los empleados se eligen por su nombre', (tester) async {
    StaffMember? chosen;
    await pump(
      tester,
      StaffPicker(
        staff: const [
          StaffMember(
            id: 's1',
            name: 'Luis Pérez',
            role: StaffRole.cashier,
            active: true,
          ),
          StaffMember(
            id: 's2',
            name: 'Marta',
            role: StaffRole.manager,
            active: true,
          ),
        ],
        onSelected: (member) => chosen = member,
      ),
    );

    expect(find.text('LP'), findsOneWidget);
    expect(find.text('Gerente'), findsOneWidget);
    await tester.tap(find.text('Marta'));
    expect(chosen?.id, 's2');
  });
}
