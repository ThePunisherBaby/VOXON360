import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90_owner/data/owner_repository.dart';
import 'package:voxon90_owner/domain/link_code.dart';
import 'package:voxon90_owner/format.dart';
import 'package:voxon90_owner/providers.dart';

/// Resumen del negocio: hoy, días anteriores, lo que necesita atención y las cajas.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final status = ref
        .watch(
          snapshotProvider((businessId: widget.businessId, name: 'status')),
        )
        .value;
    final syncedAt = status?['syncedAt'];

    return Scaffold(
      appBar: AppBar(
        title: Text(status?['businessName'] as String? ?? 'Mi negocio'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'cambiar') {
                ref.read(selectedBusinessProvider.notifier).select(null);
              } else {
                ref.read(ownerRepositoryProvider).signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'cambiar',
                child: Text('Cambiar de negocio'),
              ),
              PopupMenuItem(value: 'salir', child: Text('Salir')),
            ],
          ),
        ],
        bottom: syncedAt is! DateTime
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Actualizado ${formatTime(syncedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: switch (_tab) {
        0 => _TodayTab(businessId: widget.businessId),
        1 => _DaysTab(businessId: widget.businessId),
        2 => _AlertsTab(businessId: widget.businessId),
        _ => _DevicesTab(businessId: widget.businessId),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Hoy',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Días',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Atención',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Cajas',
          ),
        ],
      ),
    );
  }
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(
      snapshotProvider((businessId: businessId, name: 'status')),
    );
    final days = ref.watch(daysProvider(businessId)).value ?? const [];
    final today = days.isEmpty ? const <String, dynamic>{} : days.first;

    return status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message('$error'),
      data: (data) {
        if (data == null) {
          return const _Message(
            'Todavía no llegan datos de tu caja.\nVincúlala desde la pestaña «Cajas».',
          );
        }
        final sales = mapOf(data['todaySales']);
        final cash = mapOf(data['openCashSession']);
        final payments = listOf(today['payments']);
        final products = listOf(today['topProducts']);
        final recent = listOf(today['recentSales']);
        final count = intOf(sales['count']);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ventas de hoy', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(intOf(sales['totalCents'])),
                      style: theme.textTheme.displaySmall,
                    ),
                    Text(
                      count == 0
                          ? 'Sin ventas todavía'
                          : '$count ${count == 1 ? 'venta' : 'ventas'} · ITBIS ${formatMoney(intOf(sales['taxCents']))}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  icon: Icons.savings_outlined,
                  label: cash.isEmpty
                      ? 'Caja cerrada'
                      : 'En caja ${formatMoney(intOf(cash['expectedCashCents']))}',
                ),
                if (intOf(data['openOrders']) > 0)
                  _Pill(
                    icon: Icons.table_restaurant_outlined,
                    label: '${intOf(data['openOrders'])} órdenes abiertas',
                  ),
                if (intOf(data['lowStockCount']) > 0)
                  _Pill(
                    icon: Icons.inventory_2_outlined,
                    label: '${intOf(data['lowStockCount'])} bajo el mínimo',
                  ),
                if (intOf(data['receivablesCents']) > 0)
                  _Pill(
                    icon: Icons.handshake_outlined,
                    label:
                        'Fiao ${formatMoney(intOf(data['receivablesCents']))}',
                  ),
              ],
            ),
            _Section(
              title: 'Cobros de hoy',
              empty: 'Sin cobros todavía',
              children: [
                for (final payment in payments)
                  ListTile(
                    dense: true,
                    title: Text(paymentLabel(stringOf(payment['method']))),
                    trailing: Text(formatMoney(intOf(payment['amountCents']))),
                  ),
              ],
            ),
            _Section(
              title: 'Lo más vendido',
              empty: 'Sin ventas todavía',
              children: [
                for (final product in products)
                  ListTile(
                    dense: true,
                    title: Text(stringOf(product['description'])),
                    subtitle: Text(
                      '${formatQuantity(intOf(product['quantityMilli']))} vendidos',
                    ),
                    trailing: Text(formatMoney(intOf(product['netCents']))),
                  ),
              ],
            ),
            _Section(
              title: 'Últimas ventas',
              empty: 'Sin ventas todavía',
              children: [
                for (final sale in recent)
                  ListTile(
                    dense: true,
                    title: Text('Venta #${intOf(sale['number'])}'),
                    subtitle: Text(
                      [
                        stringOf(sale['cashierName']),
                        if (sale['customerName'] != null)
                          stringOf(sale['customerName']),
                        if (stringOf(sale['status']) == 'voided') 'anulada',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatMoney(intOf(sale['totalCents'])),
                      style: stringOf(sale['status']) == 'voided'
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DaysTab extends ConsumerWidget {
  const _DaysTab({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return ref
        .watch(daysProvider(businessId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message('$error'),
          data: (days) => days.isEmpty
              ? const _Message('Todavía no hay días con ventas.')
              : ListView(
                  children: [
                    for (final day in days)
                      ExpansionTile(
                        title: Text(formatDayLabel(stringOf(day['day']), now)),
                        subtitle: Text(
                          '${intOf(mapOf(day['sales'])['count'])} ventas',
                        ),
                        trailing: Text(
                          formatMoney(intOf(mapOf(day['sales'])['totalCents'])),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        children: [
                          for (final payment in listOf(day['payments']))
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.payments_outlined),
                              title: Text(
                                paymentLabel(stringOf(payment['method'])),
                              ),
                              trailing: Text(
                                formatMoney(intOf(payment['amountCents'])),
                              ),
                            ),
                          for (final product in listOf(day['topProducts']))
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.local_offer_outlined),
                              title: Text(stringOf(product['description'])),
                              trailing: Text(
                                formatMoney(intOf(product['netCents'])),
                              ),
                            ),
                          if (intOf(mapOf(day['voided'])['count']) > 0)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.block_outlined),
                              title: Text(
                                '${intOf(mapOf(day['voided'])['count'])} ventas anuladas',
                              ),
                              trailing: Text(
                                formatMoney(
                                  intOf(mapOf(day['voided'])['totalCents']),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
        );
  }
}

class _AlertsTab extends ConsumerWidget {
  const _AlertsTab({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref
        .watch(snapshotProvider((businessId: businessId, name: 'inventory')))
        .value;
    final receivables = ref
        .watch(snapshotProvider((businessId: businessId, name: 'receivables')))
        .value;
    final cash = ref
        .watch(snapshotProvider((businessId: businessId, name: 'cash')))
        .value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Bajo el mínimo',
          empty: 'El inventario está en orden',
          children: [
            for (final product in listOf(inventory?['lowStock']))
              ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(stringOf(product['name'])),
                trailing: Text(
                  'Quedan ${formatQuantity(intOf(product['stockMilli']))}',
                ),
              ),
          ],
        ),
        _Section(
          title: 'Clientes que deben',
          empty: 'Nadie debe',
          children: [
            for (final customer in listOf(receivables?['customers']))
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(stringOf(customer['name'])),
                subtitle: customer['phone'] == null
                    ? null
                    : Text(stringOf(customer['phone'])),
                trailing: Text(formatMoney(intOf(customer['balanceCents']))),
              ),
          ],
        ),
        _Section(
          title: 'Últimas cajas',
          empty: 'Todavía no se ha cerrado una caja',
          children: [
            for (final session in listOf(cash?['sessions']))
              ListTile(
                dense: true,
                leading: Icon(
                  session['closedAt'] == null
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                title: Text(
                  session['closedAt'] == null
                      ? 'Abierta por ${stringOf(session['openedByName'])}'
                      : 'Cerrada por ${stringOf(session['closedByName'])}',
                ),
                subtitle: Text(
                  'Esperado ${formatMoney(intOf(session['expectedCashCents']))}',
                ),
                trailing: session['differenceCents'] == null
                    ? null
                    : Text(
                        _difference(intOf(session['differenceCents'])),
                        style: TextStyle(
                          color: intOf(session['differenceCents']) == 0
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
              ),
          ],
        ),
      ],
    );
  }

  static String _difference(int cents) => switch (cents) {
    0 => 'Cuadró',
    < 0 => 'Faltó ${formatMoney(-cents)}',
    _ => 'Sobró ${formatMoney(cents)}',
  };
}

/// Cajas vinculadas y el código para vincular una nueva.
class _DevicesTab extends ConsumerStatefulWidget {
  const _DevicesTab({required this.businessId});

  final String businessId;

  @override
  ConsumerState<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends ConsumerState<_DevicesTab> {
  LinkCode? _code;
  Timer? _ticker;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _createCode() async {
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(ownerRepositoryProvider)
          .createLinkCode(widget.businessId);
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          if (_code != null &&
              timeLeft(_code!.expiresAt, DateTime.now()) == null) {
            _code = null;
            _ticker?.cancel();
          }
        });
      });
      if (mounted) setState(() => _code = code);
    } on OwnerException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(LinkedDevice device) async {
    try {
      await ref
          .read(ownerRepositoryProvider)
          .removeDevice(widget.businessId, device.uid);
    } on OwnerException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices =
        ref.watch(devicesProvider(widget.businessId)).value ?? const [];
    final code = _code;
    final left = code == null ? null : timeLeft(code.expiresAt, DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (code != null && left != null)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Escribe este código en tu caja principal:'),
                  const SizedBox(height: 8),
                  SelectableText(
                    formatLinkCode(code.code),
                    style: theme.textTheme.displaySmall?.copyWith(
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Vence en ${formatCountdown(left)}'),
                  const SizedBox(height: 4),
                  Text(
                    'En la caja: Ajustes → App del dueño → Vincular',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            onPressed: _busy ? null : _createCode,
            icon: const Icon(Icons.link),
            label: const Text('Vincular una caja'),
          ),
        ),
        _Section(
          title: 'Cajas vinculadas',
          empty: 'Ninguna caja está enviando datos todavía',
          children: [
            for (final device in devices)
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: Text(device.name),
                subtitle: device.linkedAt == null
                    ? null
                    : Text(
                        'Vinculada el ${formatDay(device.linkedAt!.toLocal().toString().substring(0, 10))}',
                      ),
                trailing: IconButton(
                  tooltip: 'Quitar',
                  onPressed: () => _remove(device),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ],
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

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

// El resumen llega como JSON de Firestore: se lee con cuidado por si falta algo.
int intOf(Object? value) => value is num ? value.toInt() : 0;

String stringOf(Object? value) => value is String ? value : '';

Map<String, dynamic> mapOf(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<Map<String, dynamic>> listOf(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) item,
      ]
    : const [];
