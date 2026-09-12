import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/format/money_format.dart';
import 'package:voxon90/features/kitchen/domain/kitchen_queue.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Cola de cocina y bar; null muestra todas las estaciones.
final kitchenQueueProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      station,
    ) async {
      final client = ref.watch(voxonClientProvider);
      if (client == null) return const [];
      final result = await client.call(
        'restaurant.kitchen.queue',
        station == null ? const {} : {'station': station},
      );
      return (result! as List).cast<Map<String, dynamic>>();
    });

String kitchenStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'pending' => l10n.statusPending,
      'sent' => l10n.statusSent,
      'preparing' => l10n.statusPreparing,
      'ready' => l10n.statusReady,
      'served' => l10n.statusServed,
      _ => l10n.statusCancelled,
    };

String orderTitle(AppLocalizations l10n, String kind, String? tableName) =>
    switch (kind) {
      'dine_in' => tableName ?? '',
      'takeout' => l10n.orderTakeout,
      _ => l10n.orderDelivery,
    };

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage({super.key});

  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage> {
  String? _station;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Actualiza los minutos de espera y cubre cortes de la conexión en vivo.
    _refresh = Timer.periodic(
      const Duration(seconds: 20),
      (_) => ref.invalidate(kitchenQueueProvider),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _advance(String itemId, String status) async {
    try {
      await ref.read(voxonClientProvider)!.call(
        'restaurant.kitchen.updateItem',
        {'itemId': itemId, 'status': status},
      );
      ref.invalidate(kitchenQueueProvider);
    } on BackendException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    ref.listen(backendChangesProvider, (previous, next) {
      if ((next.value?.method ?? '').startsWith('restaurant.')) {
        ref.invalidate(kitchenQueueProvider);
      }
    });
    final queue = ref.watch(kitchenQueueProvider(_station));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navKitchen),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'all', label: Text(l10n.kitchenAll)),
                ButtonSegment(
                  value: 'kitchen',
                  label: Text(l10n.kitchenStationKitchen),
                ),
                ButtonSegment(
                  value: 'bar',
                  label: Text(l10n.kitchenStationBar),
                ),
              ],
              selected: {_station ?? 'all'},
              onSelectionChanged: (selection) => setState(
                () => _station = selection.first == 'all'
                    ? null
                    : selection.first,
              ),
            ),
          ),
        ),
      ),
      body: queue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) {
          final orders = groupKitchenQueue(items);
          if (orders.isEmpty) {
            return Center(child: Text(l10n.kitchenEmpty));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 320,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final waited = minutesWaiting(order.oldestSentAt, now);
              final waitColor = waited >= 20
                  ? theme.colorScheme.error
                  : waited >= 10
                  ? Colors.orange
                  : theme.colorScheme.primary;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#${order.orderNumber} · ${orderTitle(l10n, order.orderKind, order.tableName)}',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Chip(
                            label: Text(l10n.kitchenMinutes(waited)),
                            side: BorderSide(color: waitColor),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item in order.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${formatQuantity(item['quantityMilli'] as int)} × ${item['productName']}',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    if (item['notes'] != null)
                                      Text(
                                        item['notes'] as String,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          kitchenStatusLabel(
                                            l10n,
                                            item['status'] as String,
                                          ),
                                        ),
                                        for (final next in nextKitchenActions(
                                          item['status'] as String,
                                        ))
                                          next == 'ready'
                                              ? FilledButton(
                                                  onPressed: () => _advance(
                                                    item['itemId'] as String,
                                                    next,
                                                  ),
                                                  child: Text(
                                                    kitchenStatusLabel(
                                                      l10n,
                                                      next,
                                                    ),
                                                  ),
                                                )
                                              : OutlinedButton(
                                                  onPressed: () => _advance(
                                                    item['itemId'] as String,
                                                    next,
                                                  ),
                                                  child: Text(
                                                    kitchenStatusLabel(
                                                      l10n,
                                                      next,
                                                    ),
                                                  ),
                                                ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
