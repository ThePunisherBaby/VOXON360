import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/app/router.dart';
import 'package:voxon90/app/routes.dart';
import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/backend/voxon_client.dart';

final server = Uri.parse('http://192.168.1.10:8090');
const colmado = AsyncData(
  BusinessStatus(configured: true, businessType: 'colmado'),
);
const restaurant = AsyncData(
  BusinessStatus(configured: true, businessType: 'restaurant'),
);

Employee employee(String role) => Employee(id: 'u', name: 'Ana', role: role);

void main() {
  group('resolveRedirect', () {
    test('sigue el orden conectar → configurar → PIN', () {
      expect(
        resolveRedirect(
          location: AppRoutes.loading,
          serverUri: null,
          status: const AsyncLoading(),
          employee: null,
        ),
        AppRoutes.connect,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.loading,
          serverUri: server,
          status: const AsyncError(
            BackendException(BackendException.offline, 'Sin conexión'),
            StackTrace.empty,
          ),
          employee: null,
        ),
        AppRoutes.offline,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.connect,
          serverUri: server,
          status: const AsyncLoading(),
          employee: null,
        ),
        AppRoutes.loading,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.loading,
          serverUri: server,
          status: const AsyncData(BusinessStatus(configured: false)),
          employee: null,
        ),
        AppRoutes.setup,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.setup,
          serverUri: server,
          status: colmado,
          employee: null,
        ),
        AppRoutes.login,
      );
    });

    test('con sesión lleva a la primera sección permitida', () {
      expect(
        resolveRedirect(
          location: AppRoutes.login,
          serverUri: server,
          status: colmado,
          employee: employee('owner'),
        ),
        AppRoutes.summary,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.login,
          serverUri: server,
          status: restaurant,
          employee: employee('kitchen'),
        ),
        AppRoutes.kitchen,
      );
    });

    test('no deja entrar a secciones de otro rol o tipo de negocio', () {
      expect(
        resolveRedirect(
          location: AppRoutes.summary,
          serverUri: server,
          status: colmado,
          employee: employee('cashier'),
        ),
        AppRoutes.sell,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.tables,
          serverUri: server,
          status: colmado,
          employee: employee('owner'),
        ),
        AppRoutes.summary,
      );
      expect(
        resolveRedirect(
          location: AppRoutes.tables,
          serverUri: server,
          status: restaurant,
          employee: employee('waiter'),
        ),
        isNull,
      );
    });
  });

  test('secciones por rol', () {
    List<String> paths(String role, {required bool restaurant}) => [
      for (final section in sectionsFor(role, restaurant: restaurant))
        section.path,
    ];

    expect(paths('owner', restaurant: true), [
      AppRoutes.summary,
      AppRoutes.sell,
      AppRoutes.tables,
      AppRoutes.kitchen,
      AppRoutes.settings,
    ]);
    expect(paths('cashier', restaurant: false), [
      AppRoutes.sell,
      AppRoutes.settings,
    ]);
    expect(paths('waiter', restaurant: true), [
      AppRoutes.tables,
      AppRoutes.kitchen,
      AppRoutes.settings,
    ]);
    expect(paths('kitchen', restaurant: true), [
      AppRoutes.kitchen,
      AppRoutes.settings,
    ]);
  });
}
