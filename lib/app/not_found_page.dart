import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:voxon90/app/routes.dart';
import 'package:voxon90/l10n/app_localizations.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.notFoundTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.home),
              child: Text(l10n.notFoundAction),
            ),
          ],
        ),
      ),
    );
  }
}
