import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Vínculo de la caja principal con la app del dueño (Firebase).
final cloudStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const {};
  return await client.call('cloud.status') as Map<String, dynamic>;
});

/// Estado de la sincronización y el código para vincular la app del dueño.
class CloudLinkCard extends ConsumerStatefulWidget {
  const CloudLinkCard({super.key, required this.canEdit});

  /// Solo el dueño vincula o desvincula; el gerente ve el estado.
  final bool canEdit;

  @override
  ConsumerState<CloudLinkCard> createState() => _CloudLinkCardState();
}

class _CloudLinkCardState extends ConsumerState<CloudLinkCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(voxonClientProvider)!.call(method, params);
      _code.clear();
      ref.invalidate(cloudStatusProvider);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _link() => _run('cloud.link', {'code': _code.text.trim()});

  String _stateLabel(AppLocalizations l10n, Map<String, dynamic> status) {
    final lastSync = DateTime.tryParse(status['lastSyncAt'] as String? ?? '');
    return switch (status['state']) {
      'ok' when lastSync != null => l10n.cloudStateOk(
        MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(lastSync.toLocal())),
      ),
      'offline' => l10n.cloudStateOffline,
      'error' => status['lastError'] as String? ?? l10n.cloudStatePending,
      _ => l10n.cloudStatePending,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    ref.listen(backendChangesProvider, (previous, next) {
      if ((next.value?.method ?? '').startsWith('cloud.')) {
        ref.invalidate(cloudStatusProvider);
      }
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ref
            .watch(cloudStatusProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('$error'),
              data: (status) {
                if (status['configured'] != true) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(l10n.cloudNotConfigured),
                  );
                }
                if (status['linked'] == true) {
                  final failed = status['state'] == 'error';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          failed
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_done_outlined,
                          color: failed ? theme.colorScheme.error : null,
                        ),
                        title: Text(l10n.cloudLinked),
                        subtitle: Text(_stateLabel(l10n, status)),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      if (widget.canEdit)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run('cloud.unlink'),
                            child: Text(l10n.cloudUnlinkAction),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.cloudLinkHint),
                    if (widget.canEdit) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        maxLength: 9,
                        decoration: InputDecoration(
                          labelText: l10n.cloudCodeLabel,
                          hintText: 'ABCD-2345',
                          errorText: _error,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _link(),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _link,
                        icon: const Icon(Icons.link),
                        label: Text(l10n.cloudLinkAction),
                      ),
                    ],
                  ],
                );
              },
            ),
      ),
    );
  }
}
