import 'package:voxon90/app/routes.dart';
import 'package:voxon90/l10n/app_localizations.dart';

String roleLabel(AppLocalizations l10n, String role) => switch (role) {
  'owner' => l10n.roleOwner,
  'manager' => l10n.roleManager,
  'cashier' => l10n.roleCashier,
  'waiter' => l10n.roleWaiter,
  'kitchen' => l10n.roleKitchen,
  _ => role,
};

String sectionLabel(AppLocalizations l10n, String path) => switch (path) {
  AppRoutes.summary => l10n.navSummary,
  AppRoutes.sell => l10n.navSell,
  AppRoutes.tables => l10n.navTables,
  AppRoutes.kitchen => l10n.navKitchen,
  AppRoutes.settings => l10n.navSettings,
  _ => path,
};
