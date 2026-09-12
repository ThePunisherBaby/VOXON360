import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:voxon90/app/labels.dart';
import 'package:voxon90/app/not_found_page.dart';
import 'package:voxon90/app/routes.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/backend/voxon_client.dart';
import 'package:voxon90/core/widgets/adaptive_scaffold.dart';
import 'package:voxon90/features/connection/presentation/connect_page.dart';
import 'package:voxon90/features/connection/presentation/login_page.dart';
import 'package:voxon90/features/connection/presentation/setup_page.dart';
import 'package:voxon90/features/connection/presentation/status_pages.dart';
import 'package:voxon90/features/kitchen/presentation/kitchen_page.dart';
import 'package:voxon90/features/sell/presentation/sell_page.dart';
import 'package:voxon90/features/settings/presentation/settings_page.dart';
import 'package:voxon90/features/summary/presentation/summary_page.dart';
import 'package:voxon90/features/tables/presentation/tables_page.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Sección principal y quién la ve.
class AppSection {
  const AppSection({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.roles,
    this.restaurantOnly = false,
  });

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final Set<String> roles;

  /// Mesas y cocina solo tienen sentido en restaurantes.
  final bool restaurantOnly;
}

const appSections = [
  AppSection(
    path: AppRoutes.summary,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    roles: {'owner', 'manager'},
  ),
  AppSection(
    path: AppRoutes.sell,
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    roles: {'owner', 'manager', 'cashier'},
  ),
  AppSection(
    path: AppRoutes.tables,
    icon: Icons.table_restaurant_outlined,
    selectedIcon: Icons.table_restaurant,
    roles: {'owner', 'manager', 'cashier', 'waiter'},
    restaurantOnly: true,
  ),
  AppSection(
    path: AppRoutes.kitchen,
    icon: Icons.soup_kitchen_outlined,
    selectedIcon: Icons.soup_kitchen,
    roles: {'owner', 'manager', 'waiter', 'kitchen'},
    restaurantOnly: true,
  ),
  AppSection(
    path: AppRoutes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    roles: {'owner', 'manager', 'cashier', 'waiter', 'kitchen'},
  ),
];

/// Secciones visibles para un rol en un tipo de negocio.
List<AppSection> sectionsFor(String role, {required bool restaurant}) => [
  for (final section in appSections)
    if (section.roles.contains(role) && (!section.restaurantOnly || restaurant))
      section,
];

/// A dónde debe ir la app según la conexión, el negocio y la sesión.
/// Devuelve null si la ubicación actual es correcta.
String? resolveRedirect({
  required String location,
  required Uri? serverUri,
  required AsyncValue<BusinessStatus> status,
  required Employee? employee,
}) {
  String? goTo(String target) => location == target ? null : target;

  if (serverUri == null) return goTo(AppRoutes.connect);
  if (status.hasError && !status.isLoading) return goTo(AppRoutes.offline);
  final business = status.value;
  if (business == null) return goTo(AppRoutes.loading);
  if (!business.configured) return goTo(AppRoutes.setup);
  if (employee == null) return goTo(AppRoutes.login);

  final sections = sectionsFor(
    employee.role,
    restaurant: business.businessType == 'restaurant',
  );
  if (sections.any((section) => section.path == location)) return null;
  return sections.first.path;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Cualquier cambio de conexión, negocio o sesión vuelve a evaluar la ruta.
  final refresh = ValueNotifier<int>(0);
  ref.listen(serverUriProvider, (previous, next) => refresh.value++);
  ref.listen(businessStatusProvider, (previous, next) => refresh.value++);
  ref.listen(sessionProvider, (previous, next) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.loading,
    refreshListenable: refresh,
    errorBuilder: (context, state) => const NotFoundPage(),
    redirect: (context, state) => resolveRedirect(
      location: state.matchedLocation,
      serverUri: ref.read(serverUriProvider),
      status: ref.read(businessStatusProvider),
      employee: ref.read(sessionProvider),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) => const ConnectPage(),
      ),
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const LoadingPage(),
      ),
      GoRoute(
        path: AppRoutes.offline,
        builder: (context, state) => const OfflinePage(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (context, state) => const SetupPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.summary,
            builder: (context, state) => const SummaryPage(),
          ),
          GoRoute(
            path: AppRoutes.sell,
            builder: (context, state) => const SellPage(),
          ),
          GoRoute(
            path: AppRoutes.tables,
            builder: (context, state) => const TablesPage(),
          ),
          GoRoute(
            path: AppRoutes.kitchen,
            builder: (context, state) => const KitchenPage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Marco de las secciones con la navegación que corresponde al rol.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(sessionProvider);
    final business = ref.watch(businessStatusProvider).value;
    if (employee == null || business == null) return child;

    final sections = sectionsFor(
      employee.role,
      restaurant: business.businessType == 'restaurant',
    );
    if (sections.length < 2) return child;

    final l10n = AppLocalizations.of(context);
    final selected = sections.indexWhere((section) => section.path == location);
    return AdaptiveScaffold(
      selectedIndex: selected < 0 ? 0 : selected,
      onDestinationSelected: (index) => context.go(sections[index].path),
      destinations: [
        for (final section in sections)
          AppDestination(
            icon: section.icon,
            selectedIcon: section.selectedIcon,
            label: sectionLabel(l10n, section.path),
          ),
      ],
      body: child,
    );
  }
}
