import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/format/money_format.dart';
import 'package:voxon90/features/sell/presentation/sell_page.dart';
import 'package:voxon90/l10n/app_localizations.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const {};
  return await client.call('reports.dashboard') as Map<String, dynamic>;
});

final lowStockProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const [];
  return ((await client.call('inventory.lowStock'))! as List)
      .cast<Map<String, dynamic>>();
});

final receivablesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const {};
  return await client.call('reports.receivables') as Map<String, dynamic>;
});

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Resumen del dueño o gerente: el día en números, la caja y lo que requiere atención.
class SummaryPage extends ConsumerWidget {
  const SummaryPage({super.key});

  void _reload(WidgetRef ref) {
    ref
      ..invalidate(dashboardProvider)
      ..invalidate(lowStockProvider)
      ..invalidate(receivablesProvider);
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final result =
          await ref.read(voxonClientProvider)!.call('system.backup')
              as Map<String, dynamic>;
      if (context.mounted) {
        _snack(context, l10n.backupDone('${result['path']}'));
      }
    } on BackendException catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(backendChangesProvider, (previous, next) {
      final method = next.value?.method ?? '';
      if (RegExp(
        r'^(sales|cash|customers|inventory|restaurant)\.',
      ).hasMatch(method)) {
        _reload(ref);
      }
    });
    final dashboard = ref.watch(dashboardProvider);
    final isOwner = ref.watch(sessionProvider)?.role == 'owner';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          dashboard.value?['day'] is String
              ? l10n.summaryTitle(dashboard.value!['day'] as String)
              : l10n.navSummary,
        ),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: l10n.backupAction,
              onPressed: () => _backup(context, ref),
              icon: const Icon(Icons.backup_outlined),
            ),
        ],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (data) {
          final sales = data['sales'] as Map<String, dynamic>? ?? const {};
          final topProducts = (data['topProducts'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final payments = (data['payments'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () async {
              _reload(ref);
              await ref.read(dashboardProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Tile(
                      label: l10n.summarySales,
                      value: formatMoney(sales['totalCents'] as int? ?? 0),
                      detail: l10n.summaryTickets(
                        sales['count'] as int? ?? 0,
                        formatMoney(sales['averageTicketCents'] as int? ?? 0),
                      ),
                    ),
                    _Tile(
                      label: l10n.summaryTaxCollected,
                      value: formatMoney(sales['taxCents'] as int? ?? 0),
                    ),
                    _Tile(
                      label: l10n.sellTip,
                      value: formatMoney(sales['tipCents'] as int? ?? 0),
                    ),
                    _Tile(
                      label: l10n.summaryReceivables,
                      value: formatMoney(data['receivablesCents'] as int? ?? 0),
                    ),
                    _Tile(
                      label: l10n.summaryVoided,
                      value: '${data['voidedSales'] ?? 0}',
                    ),
                    _Tile(
                      label: l10n.summaryOpenOrders,
                      value: '${data['openOrders'] ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _CashCard(
                  session: data['openCashSession'] as Map<String, dynamic>?,
                ),
                _Section(
                  title: l10n.summaryTopProducts,
                  empty: l10n.summaryNoSales,
                  children: [
                    for (final product in topProducts)
                      ListTile(
                        dense: true,
                        title: Text(product['description'] as String),
                        subtitle: Text(
                          formatQuantity(product['quantityMilli'] as int),
                        ),
                        trailing: Text(formatMoney(product['netCents'] as int)),
                      ),
                  ],
                ),
                _Section(
                  title: l10n.summaryPayments,
                  empty: l10n.summaryNoSales,
                  children: [
                    for (final payment in payments)
                      ListTile(
                        dense: true,
                        title: Text(
                          paymentLabel(l10n, payment['method'] as String),
                        ),
                        trailing: Text(
                          formatMoney(payment['amountCents'] as int),
                        ),
                      ),
                  ],
                ),
                const _LowStockSection(),
                const _DebtorsSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.headlineSmall),
              if (detail != null)
                Text(detail!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.children,
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (children.isEmpty)
              Padding(padding: const EdgeInsets.all(12), child: Text(empty))
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _LowStockSection extends ConsumerWidget {
  const _LowStockSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(lowStockProvider).value ?? const [];
    return _Section(
      title: l10n.summaryLowStock,
      empty: l10n.summaryStockOk,
      children: [
        for (final product in items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(product['name'] as String),
            trailing: Text(
              '${formatQuantity(product['stockMilli'] as int)} ${unitLabel(product['unit'] as String)}',
            ),
          ),
      ],
    );
  }
}

class _DebtorsSection extends ConsumerWidget {
  const _DebtorsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final customers =
        ((ref.watch(receivablesProvider).value?['customers'] as List?) ??
                const [])
            .cast<Map<String, dynamic>>();
    return _Section(
      title: l10n.summaryDebtors,
      empty: l10n.summaryNoDebtors,
      children: [
        for (final customer in customers.take(10))
          ListTile(
            dense: true,
            title: Text(customer['name'] as String),
            subtitle: customer['phone'] == null
                ? null
                : Text(customer['phone'] as String),
            trailing: Text(formatMoney(customer['balanceCents'] as int)),
          ),
      ],
    );
  }
}

class _CashCard extends ConsumerStatefulWidget {
  const _CashCard({required this.session});

  final Map<String, dynamic>? session;

  @override
  ConsumerState<_CashCard> createState() => _CashCardState();
}

class _CashCardState extends ConsumerState<_CashCard> {
  final _counted = TextEditingController();
  bool _closing = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final l10n = AppLocalizations.of(context);
    final cents = parseMoney(_counted.text);
    if (cents == null || cents < 0) {
      _snack(context, l10n.invalidAmount);
      return;
    }
    setState(() => _closing = true);
    try {
      final closed =
          await ref.read(voxonClientProvider)!.call('cash.close', {
                'countedCashCents': cents,
              })
              as Map<String, dynamic>;
      final difference = closed['differenceCents'] as int? ?? 0;
      if (mounted) {
        _snack(
          context,
          difference == 0
              ? l10n.cashClosedExact
              : l10n.cashClosedDifference(formatMoney(difference)),
        );
      }
      _counted.clear();
      ref
        ..invalidate(dashboardProvider)
        ..invalidate(cashSessionProvider);
    } on BackendException catch (error) {
      if (mounted) _snack(context, error.message);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = widget.session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.summaryRegister,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (session == null)
              Text(l10n.cashClosedHint)
            else ...[
              Text(
                l10n.cashExpected(
                  formatMoney(session['expectedCashCents'] as int),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _counted,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.cashCounted,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _closing ? null : _close,
                child: Text(l10n.cashCloseAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
