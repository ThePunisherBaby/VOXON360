import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/format/money_format.dart';
import 'package:voxon90/features/kitchen/presentation/kitchen_page.dart';
import 'package:voxon90/features/sell/domain/cart.dart';
import 'package:voxon90/features/sell/presentation/sell_page.dart';
import 'package:voxon90/features/tables/domain/order_rules.dart';
import 'package:voxon90/l10n/app_localizations.dart';

final tablesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const [];
  return ((await client.call('restaurant.tables.list'))! as List)
      .cast<Map<String, dynamic>>();
});

final openOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const [];
  return ((await client.call('restaurant.orders.list'))! as List)
      .cast<Map<String, dynamic>>();
});

final orderProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  id,
) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return const {};
  return await client.call('restaurant.orders.get', {'id': id})
      as Map<String, dynamic>;
});

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Plano de mesas y la orden seleccionada: agregar, enviar a cocina y cobrar.
class TablesPage extends ConsumerStatefulWidget {
  const TablesPage({super.key});

  @override
  ConsumerState<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends ConsumerState<TablesPage> {
  String? _orderId;
  bool _busy = false;

  void _reload() {
    ref
      ..invalidate(tablesProvider)
      ..invalidate(openOrdersProvider);
  }

  void _select(String? orderId) => setState(() => _orderId = orderId);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackendException catch (error) {
      if (mounted) _snack(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrder(String kind, {String? tableId}) => _run(() async {
    final order =
        await ref.read(voxonClientProvider)!.call('restaurant.orders.open', {
              'kind': kind,
              'tableId': ?tableId,
            })
            as Map<String, dynamic>;
    _reload();
    _select(order['id'] as String);
  });

  Future<void> _addTable() async {
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _NameDialog(title: l10n.tablesAdd, label: l10n.tablesNewName),
    );
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await ref.read(voxonClientProvider)!.call('restaurant.tables.create', {
        'name': name,
      });
      ref.invalidate(tablesProvider);
    });
  }

  void _onTableTap(Map<String, dynamic> table) {
    final orderId = table['orderId'] as String?;
    if (orderId != null) {
      _select(orderId);
    } else {
      _openOrder('dine_in', tableId: table['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(backendChangesProvider, (previous, next) {
      final method = next.value?.method ?? '';
      if (method.startsWith('restaurant.') || method.startsWith('sales.')) {
        _reload();
        ref.invalidate(orderProvider);
      }
    });
    final role = ref.watch(sessionProvider)?.role ?? '';
    final orderId = _orderId;

    final floor = _Floor(
      busy: _busy,
      selectedOrderId: orderId,
      onTableTap: _onTableTap,
      onOrderTap: _select,
    );
    final actions = [
      IconButton(
        tooltip: l10n.orderTakeout,
        onPressed: _busy ? null : () => _openOrder('takeout'),
        icon: const Icon(Icons.takeout_dining_outlined),
      ),
      IconButton(
        tooltip: l10n.orderDelivery,
        onPressed: _busy ? null : () => _openOrder('delivery'),
        icon: const Icon(Icons.delivery_dining_outlined),
      ),
      if (managerRoles.contains(role))
        IconButton(
          tooltip: l10n.tablesAdd,
          onPressed: _busy ? null : _addTable,
          icon: const Icon(Icons.add),
        ),
    ];

    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navTables), actions: actions),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: floor),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: orderId == null
                  ? Center(child: Text(l10n.tablesSelectHint))
                  : _OrderPanel(
                      key: ValueKey(orderId),
                      orderId: orderId,
                      onClosed: () => _select(null),
                    ),
            ),
          ],
        ),
      );
    }
    if (orderId != null) {
      // En teléfono la orden ocupa la pantalla; "atrás" vuelve a las mesas.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(null);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => _select(null)),
            title: Text(l10n.orderBill),
          ),
          body: _OrderPanel(
            key: ValueKey(orderId),
            orderId: orderId,
            onClosed: () => _select(null),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTables), actions: actions),
      body: floor,
    );
  }
}

class _Floor extends ConsumerWidget {
  const _Floor({
    required this.busy,
    required this.selectedOrderId,
    required this.onTableTap,
    required this.onOrderTap,
  });

  final bool busy;
  final String? selectedOrderId;
  final ValueChanged<Map<String, dynamic>> onTableTap;
  final ValueChanged<String> onOrderTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final others = ordersWithoutTable(
      ref.watch(openOrdersProvider).value ?? const [],
    );

    return ref
        .watch(tablesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (tables) => CustomScrollView(
            slivers: [
              if (tables.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.tablesEmpty, textAlign: TextAlign.center),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    final orderId = table['orderId'] as String?;
                    final selected =
                        orderId != null && orderId == selectedOrderId;
                    return Card(
                      color: orderId == null
                          ? null
                          : theme.colorScheme.primaryContainer,
                      shape: selected
                          ? RoundedRectangleBorder(
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: busy ? null : () => onTableTap(table),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                table['name'] as String,
                                style: theme.textTheme.titleLarge,
                              ),
                              if (table['areaName'] != null)
                                Text(
                                  table['areaName'] as String,
                                  style: theme.textTheme.bodySmall,
                                ),
                              const Spacer(),
                              if (orderId == null)
                                Text(l10n.tablesFree)
                              else ...[
                                Text(
                                  l10n.tablesOrder(
                                    table['orderNumber'] as int,
                                    table['waiterName'] as String,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  l10n.tablesItems(
                                    table['itemCount'] as int,
                                    formatMoney(table['grossCents'] as int),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (others.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      l10n.tablesOtherOrders,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                SliverList.list(
                  children: [
                    for (final order in others)
                      ListTile(
                        selected: order['orderId'] == selectedOrderId,
                        leading: Icon(
                          order['kind'] == 'takeout'
                              ? Icons.takeout_dining_outlined
                              : Icons.delivery_dining_outlined,
                        ),
                        title: Text(
                          '#${order['number']} · ${orderTitle(l10n, order['kind'] as String, null)}',
                        ),
                        subtitle: Text(
                          l10n.tablesItems(
                            order['itemCount'] as int,
                            formatMoney(order['grossCents'] as int),
                          ),
                        ),
                        onTap: busy
                            ? null
                            : () => onOrderTap(order['orderId'] as String),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
  }
}

class _OrderPanel extends ConsumerStatefulWidget {
  const _OrderPanel({super.key, required this.orderId, required this.onClosed});

  final String orderId;

  /// La orden se cobró, se canceló o ya no está abierta.
  final VoidCallback onClosed;

  @override
  ConsumerState<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends ConsumerState<_OrderPanel> {
  final _search = TextEditingController();
  final _received = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _method = 'cash';
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _received.dispose();
    super.dispose();
  }

  /// Llama al servidor y refresca la orden y el plano. Devuelve null si falló.
  Future<Object?> _call(String method, Map<String, Object?> params) async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(voxonClientProvider)!.call(method, params);
      ref
        ..invalidate(orderProvider(widget.orderId))
        ..invalidate(tablesProvider)
        ..invalidate(openOrdersProvider);
      return result ?? true;
    } on BackendException catch (error) {
      if (mounted) _snack(context, error.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => setState(() => _query = text.trim()),
    );
  }

  Future<void> _addProduct(Map<String, dynamic> product) async {
    final added = await _call('restaurant.orders.addItems', {
      'orderId': widget.orderId,
      'items': [
        {'productId': product['id'], 'quantityMilli': 1000},
      ],
    });
    if (added != null && mounted) {
      _search.clear();
      setState(() => _query = '');
    }
  }

  // Un lector de código de barras escribe el código y presiona Enter.
  Future<void> _onSubmitted(String text) async {
    final code = text.trim();
    final client = ref.read(voxonClientProvider);
    if (code.isEmpty || client == null) return;
    try {
      final product =
          await client.call('catalog.products.get', {'barcode': code})
              as Map<String, dynamic>;
      await _addProduct(product);
    } on BackendException {
      setState(() => _query = code);
    }
  }

  Future<void> _send() async {
    final sent = await _call('restaurant.orders.send', {
      'orderId': widget.orderId,
    });
    if (sent != null && mounted) {
      _snack(context, AppLocalizations.of(context).orderSent);
    }
  }

  Future<void> _checkout(int totalCents) async {
    final l10n = AppLocalizations.of(context);
    final List<Map<String, Object>> payments;
    try {
      final text = _received.text.trim();
      int? received;
      if (_method == 'cash' && text.isNotEmpty) {
        received = parseMoney(text);
        if (received == null) throw const CartException('insufficient_cash');
      }
      payments = checkoutPayments(
        method: _method,
        totalCents: totalCents,
        receivedCents: received,
      );
    } on CartException catch (error) {
      _snack(context, cartErrorLabel(l10n, error));
      return;
    }

    final result = await _call('restaurant.orders.checkout', {
      'orderId': widget.orderId,
      'payments': payments,
    });
    if (result is! Map<String, dynamic>) return;
    ref.invalidate(cashSessionProvider);
    final sale = result['sale'] as Map<String, dynamic>;
    final change = sale['changeCents'] as int? ?? 0;
    if (mounted) {
      final charged = l10n.orderCharged(formatMoney(sale['totalCents'] as int));
      _snack(
        context,
        change > 0
            ? '$charged · ${l10n.sellChange(formatMoney(change))}'
            : charged,
      );
    }
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final role = ref.watch(sessionProvider)?.role ?? '';

    return ref
        .watch(orderProvider(widget.orderId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (order) {
            if (order['status'] != 'open') {
              // Otro equipo la cobró o la canceló.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => widget.onClosed(),
              );
              return const SizedBox.shrink();
            }
            final items = activeItems(order);
            final pending = pendingItemCount(order);
            final estimate = order['estimate'] as Map<String, dynamic>;
            final total = estimate['totalCents'] as int;
            final tip = estimate['tipCents'] as int;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '#${order['number']} · ${orderTitle(l10n, order['kind'] as String, order['tableName'] as String?)}',
                  style: theme.textTheme.titleLarge,
                ),
                Text(l10n.orderServedBy(order['waiterName'] as String)),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: l10n.orderAddProduct,
                    hintText: l10n.orderAddProductsHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSubmitted,
                ),
                if (_query.isNotEmpty)
                  _SearchResults(
                    query: _query,
                    onAdd: _busy ? null : _addProduct,
                  ),
                const SizedBox(height: 8),
                for (final item in items)
                  _OrderItemTile(
                    item: item,
                    busy: _busy,
                    canCancel: canCancelItem(item['status'] as String, role),
                    onQuantity: (milli) => _call(
                      'restaurant.orders.updateItem',
                      {'itemId': item['id'], 'quantityMilli': milli},
                    ),
                    onCancel: () => _call('restaurant.orders.cancelItem', {
                      'itemId': item['id'],
                    }),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy || pending == 0 ? null : _send,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    pending == 0
                        ? l10n.orderNothingToSend
                        : l10n.orderSend(pending),
                  ),
                ),
                const Divider(height: 32),
                Text(l10n.orderBill, style: theme.textTheme.titleMedium),
                _AmountRow(
                  label: l10n.sellSubtotal,
                  cents: estimate['subtotalCents'] as int,
                ),
                _AmountRow(
                  label: l10n.sellTax,
                  cents: estimate['taxCents'] as int,
                ),
                if (tip > 0) _AmountRow(label: l10n.sellTip, cents: tip),
                _AmountRow(
                  label: l10n.sellTotal,
                  cents: total,
                  emphasized: true,
                ),
                if (cashierRoles.contains(role) && items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in const ['cash', 'card', 'transfer'])
                        ChoiceChip(
                          label: Text(paymentLabel(l10n, method)),
                          selected: _method == method,
                          onSelected: (_) => setState(() => _method = method),
                        ),
                    ],
                  ),
                  if (_method == 'cash') ..._cashFields(l10n, total),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => _checkout(total),
                    child: Text('${l10n.orderCharge} · ${formatMoney(total)}'),
                  ),
                ],
              ],
            );
          },
        );
  }

  List<Widget> _cashFields(AppLocalizations l10n, int total) {
    final received = parseMoney(_received.text);
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _received,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: l10n.sellReceived,
          hintText: formatMoney(total),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (received != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            received >= total
                ? l10n.sellChange(formatMoney(received - total))
                : l10n.sellMissing(formatMoney(total - received)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
    ];
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.onAdd});

  final String query;
  final ValueChanged<Map<String, dynamic>>? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(productSearchProvider(query))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (products) => Card(
            child: Column(
              children: [
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l10n.sellNoProducts),
                  ),
                for (final product in products.take(6))
                  ListTile(
                    dense: true,
                    title: Text(product['name'] as String),
                    trailing: Text(formatMoney(product['priceCents'] as int)),
                    onTap: onAdd == null ? null : () => onAdd!(product),
                  ),
              ],
            ),
          ),
        );
  }
}

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile({
    required this.item,
    required this.busy,
    required this.canCancel,
    required this.onQuantity,
    required this.onCancel,
  });

  final Map<String, dynamic> item;
  final bool busy;
  final bool canCancel;
  final ValueChanged<int> onQuantity;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = item['status'] as String;
    final pending = status == 'pending';
    final quantity = item['quantityMilli'] as int;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatQuantity(quantity)} × ${item['productName']}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '${kitchenStatusLabel(l10n, status)} · ${formatMoney(item['grossCents'] as int)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (item['notes'] != null)
                  Text(
                    item['notes'] as String,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (pending && quantity > 1000)
            IconButton(
              onPressed: busy ? null : () => onQuantity(quantity - 1000),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          if (pending)
            IconButton(
              onPressed: busy ? null : () => onQuantity(quantity + 1000),
              icon: const Icon(Icons.add_circle_outline),
            ),
          if (canCancel)
            IconButton(
              tooltip: l10n.sellRemove,
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.cents,
    this.emphasized = false,
  });

  final String label;
  final int cents;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatMoney(cents), style: style),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}
