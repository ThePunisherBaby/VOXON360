import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/app/labels.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/features/settings/application/settings_controllers.dart';
import 'package:voxon90/features/settings/presentation/cloud_link_card.dart';
import 'package:voxon90/l10n/app_localizations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _systemLanguage = 'system';

  /// Nombres de los idiomas en su propia lengua; no se traducen a propósito.
  static const _languageNames = {'es': 'Español', 'en': 'English'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final employee = ref.watch(sessionProvider);
    final serverUri = ref.watch(serverUriProvider);
    final businessName = ref.watch(businessStatusProvider).value?.name;
    final seesCloud =
        employee != null &&
        (employee.role == 'owner' || employee.role == 'manager');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (employee != null) ...[
                _SectionTitle(l10n.settingsSession),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(employee.name),
                    subtitle: Text(roleLabel(l10n, employee.role)),
                    trailing: OutlinedButton(
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).logout(),
                      child: Text(l10n.logout),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (serverUri != null) ...[
                _SectionTitle(l10n.settingsServer),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.point_of_sale),
                    title: Text(businessName ?? l10n.appTitle),
                    subtitle: Text('$serverUri'),
                    trailing: TextButton(
                      onPressed: () async {
                        await ref.read(sessionProvider.notifier).logout();
                        await ref.read(serverUriProvider.notifier).forget();
                      },
                      child: Text(l10n.loginChangeServer),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (seesCloud) ...[
                _SectionTitle(l10n.settingsCloud),
                CloudLinkCard(canEdit: employee.role == 'owner'),
                const SizedBox(height: 24),
              ],
              _SectionTitle(l10n.settingsAppearance),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.themeSystem),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.themeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.themeDark),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) => ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(selection.first),
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(l10n.settingsLanguage),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: _systemLanguage,
                      label: Text(l10n.languageSystem),
                    ),
                    for (final supported in AppLocalizations.supportedLocales)
                      ButtonSegment(
                        value: supported.languageCode,
                        label: Text(
                          _languageNames[supported.languageCode] ??
                              supported.languageCode,
                        ),
                      ),
                  ],
                  selected: {locale?.languageCode ?? _systemLanguage},
                  onSelectionChanged: (selection) {
                    final code = selection.first;
                    ref
                        .read(localeProvider.notifier)
                        .setLocale(
                          code == _systemLanguage ? null : Locale(code),
                        );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
