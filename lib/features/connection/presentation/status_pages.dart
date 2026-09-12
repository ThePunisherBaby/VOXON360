import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Mientras se consulta el estado del negocio.
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// La caja principal no responde: reintentar o elegir otra.
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final error = ref.watch(businessStatusProvider).error;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64),
              const SizedBox(height: 16),
              Text(
                l10n.offlineTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.invalidate(businessStatusProvider),
                child: Text(l10n.retry),
              ),
              TextButton(
                onPressed: () => ref.read(serverUriProvider.notifier).forget(),
                child: Text(l10n.loginChangeServer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
