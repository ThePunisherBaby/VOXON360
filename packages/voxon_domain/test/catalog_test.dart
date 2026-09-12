import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:voxon_domain/src/catalog/catalog_data.g.dart';
import 'package:voxon_domain/voxon_domain.dart';

void main() {
  test('los catálogos incluidos son idénticos a shared/', () {
    const hint = 'Corre: dart run tool/sync_catalogs.dart';
    expect(
      jsonDecode(modesJson),
      jsonDecode(File('../../shared/modes.json').readAsStringSync()),
      reason: hint,
    );
    expect(
      jsonDecode(plansJson),
      jsonDecode(File('../../shared/plans.json').readAsStringSync()),
      reason: hint,
    );
  });

  group('modos de negocio', () {
    final catalog = ModeCatalog.standard;

    test('son 20 y los cuatro prioritarios se pueden elegir', () {
      expect(catalog.modes, hasLength(20));
      expect(catalog.modes.map((mode) => mode.order), [
        for (var i = 1; i <= 20; i++) i,
      ]);
      expect(catalog.available.map((mode) => mode.id), [
        'supermarket',
        'colmado',
        'restaurant',
        'store',
      ]);
      expect(catalog.byId('laundry')!.isAvailable, isFalse);
      expect(catalog.byId('casino'), isNull);
    });

    test('el restaurante trae mesas, cocina y propina legal', () {
      final restaurant = catalog.byId('restaurant')!;
      expect(restaurant.priceMode, PriceMode.taxExcluded);
      expect(restaurant.legalTip, isTrue);
      expect(restaurant.uses('tables'), isTrue);
      expect(restaurant.uses('kitchen'), isTrue);
      expect(restaurant.stations, ['Cocina', 'Bar']);
      expect(restaurant.colorValue, 0xFFC62828);
    });

    test('el colmado y el supermercado venden con ITBIS incluido', () {
      final colmado = catalog.byId('colmado')!;
      final supermarket = catalog.byId('supermarket')!;
      expect(colmado.priceMode, PriceMode.taxIncluded);
      expect(colmado.uses('credit'), isTrue);
      expect(colmado.uses('fractions'), isTrue);
      expect(supermarket.uses('scale'), isTrue);
      expect(supermarket.uses('multiRegister'), isTrue);
      expect(supermarket.legalTip, isFalse);
    });

    test('cada módulo que usa un modo tiene descripción', () {
      for (final mode in catalog.modes) {
        for (final module in mode.modules) {
          expect(
            catalog.moduleNames,
            contains(module),
            reason: '${mode.id} usa $module',
          );
        }
      }
    });

    test('los colores se leen con o sin numeral', () {
      expect(parseHexColor('#2E7D32'), 0xFF2E7D32);
      expect(parseHexColor('802E7D32'), 0x802E7D32);
      expect(() => parseHexColor('verde'), throwsFormatException);
    });
  });

  group('planes', () {
    final plans = PlanCatalog.standard;

    test('la prueba gratis es del plan 90 por 14 días', () {
      expect(plans.trialTier, PlanTier.v90);
      expect(plans.trialDays, 14);
    });

    test('las cajas con VOXON POS vienen desde el 90', () {
      expect(plans.of(PlanTier.v45).has('posDevices'), isFalse);
      expect(plans.lowestWith('posDevices'), PlanTier.v90);
      expect(plans.of(PlanTier.v90).limits.devices, 3);
      expect(plans.of(PlanTier.v180).limits.devices, 10);
    });

    test('cada plan incluye todo lo del anterior', () {
      for (var i = 1; i < PlanTier.values.length; i++) {
        final lower = plans.of(PlanTier.values[i - 1]);
        final higher = plans.of(PlanTier.values[i]);
        expect(
          higher.features.containsAll(lower.features),
          isTrue,
          reason: '${higher.name} debe incluir ${lower.name}',
        );
      }
    });

    test('cero es sin tope', () {
      expect(
        PlanLimits.allows(999, plans.of(PlanTier.v360).limits.devices),
        isTrue,
      );
      expect(PlanLimits.allows(3, 3), isTrue);
      expect(PlanLimits.allows(4, 3), isFalse);
      expect(PlanTier.v180.degrees, 180);
    });
  });
}
