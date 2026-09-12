import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/format/money_format.dart';
import 'package:voxon90/features/sell/application/sell_controller.dart';
import 'package:voxon90/features/sell/domain/cart.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Productos activos que coinciden con la búsqueda.
final productSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      search,
    ) async {
      final client = ref.watch(voxonClientProvider);
      if (client == null) return const [];
      final result = await client.call('catalog.products.list', {
        'search': search,
        'limit': 60,
      });
      return (result! as List).cast<Map<String, dynamic>>();
    });

/// Caja abierta, o null si está cerrada.
final cashSessionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(voxonClientProvider);
  if (client == null) return null;
  return await client.call('cash.current') as Map<String, dynamic>?;
});

String paymentLabel(AppLocalizations l10n, String method) => switch (method) {
  'card' => l10n.paymentCard,
  'transfer' => l10n.paymentTransfer,
  'credit' => l10n.paymentCredit,
  _ => l10n.paymentCash,
};

String cartErrorLabel(AppLocalizations l10n, Object error) => switch (error) {
  CartException(code: 'whole_units') => l10n.sellWholeUnits,
  CartException(code: 'insufficient_cash') => l10n.sellInsufficientCash,
  CartException(code: 'customer_required') => l10n.sellChooseCustomer,
  CartException() => l10n.sellInvalidQuantity,
  _ => '$error',
};

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class SellPage extends ConsumerStatefulWidget {
  const SellPage({super.key});

  @override
  ConsumerState<SellPage> createState() => _SellPageState();
}

class _SellPageState extends ConsumerState<SellPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => setState(() => _query = text.trim()),
    );
  }

  void _add(Map<String, dynamic> product) {
    try {
      ref.read(sellControllerProvider.notifier).add(product);
    } on CartException catch (error) {
      _showError(context, cartErrorLabel(AppLocalizations.of(context), error));
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
      _add(product);
      _search.clear();
      setState(() => _query = '');
    } on BackendException {
      setState(() => _query = code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(backendChangesProvider, (previous, next) {
      final method = next.value?.method ?? '';
      if (RegExp(r'^(catalog|inventory|sales)\.').hasMatch(method)) {
        ref.invalidate(productSearchProvider);
      }
      if (method.startsWith('cash.')) ref.invalidate(cashSessionProvider);
    });

    final products = _ProductsPanel(
      controller: _search,
      query: _query,
      onChanged: _onSearchChanged,
      onSubmitted: _onSubmitted,
      onAdd: _add,
    );
    const cart = _CartPanel();

    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navSell)),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: products),
            const VerticalDivider(width: 1),
            const SizedBox(width: 400, child: cart),
          ],
        ),
      );
    }
    final count = ref.watch(
      sellControllerProvider.select((state) => state.cart.lines.length),
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navSell),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.sellProductsTab),
              Tab(text: l10n.sellSaleTab(count)),
            ],
          ),
        ),
        body: TabBarView(children: [products, cart]),
      ),
    );
  }
}

class _ProductsPanel extends ConsumerWidget {
  const _ProductsPanel({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
    required this.onAdd,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<Map<String, dynamic>> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final products = ref.watch(productSearchProvider(query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.sellSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        Expanded(
          child: products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (items) => items.isEmpty
                ? Center(child: Text(l10n.sellNoProducts))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.35,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final product = items[index];
                      final unit = product['unit'] as String? ?? 'unit';
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onAdd(product),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['name'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                                const Spacer(),
                                Text(
                                  unit == 'unit'
                                      ? formatMoney(
                                          product['priceCents'] as int,
                                        )
                                      : '${formatMoney(product['priceCents'] as int)} / ${unitLabel(unit)}',
                                ),
                                if (product['trackStock'] == true)
                                  Text(
                                    l10n.sellStockLeft(
                                      formatQuantity(
                                        product['availableMilli'] as int,
                                      ),
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _CartPanel extends ConsumerStatefulWidget {
  const _CartPanel();

  @override
  ConsumerState<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<_CartPanel> {
  final _received = TextEditingController();
  final _openingFloat = TextEditingController();
  final _customerSearch = TextEditingController();
  List<Map<String, dynamic>> _customers = const [];
  bool _busy = false;

  @override
  void dispose() {
    _received.dispose();
    _openingFloat.dispose();
    _customerSearch.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on CartException catch (error) {
      if (mounted) {
        _showError(
          context,
          cartErrorLabel(AppLocalizations.of(context), error),
        );
      }
    } on BackendException catch (error) {
      if (mounted) _showError(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCash() => _run(() async {
    final text = _openingFloat.text.trim();
    final cents = text.isEmpty ? 0 : parseMoney(text);
    if (cents == null || cents < 0) {
      _showError(context, AppLocalizations.of(context).invalidAmount);
      return;
    }
    await ref.read(voxonClientProvider)!.call('cash.open', {
      'openingFloatCents': cents,
    });
    _openingFloat.clear();
    ref.invalidate(cashSessionProvider);
  });

  Future<void> _charge() => _run(() async {
    final text = _received.text.trim();
    int? received;
    if (text.isNotEmpty) {
      received = parseMoney(text);
      if (received == null) throw const CartException('insufficient_cash');
    }
    final sale = await ref
        .read(sellControllerProvider.notifier)
        .charge(receivedCents: received);
    _received.clear();
    _customerSearch.clear();
    _customers = const [];
    ref.invalidate(productSearchProvider);
    ref.invalidate(cashSessionProvider);
    if (mounted) {
      _showError(
        context,
        AppLocalizations.of(context).sellCharged(sale['number'] as int),
      );
    }
  });

  Future<void> _searchCustomers(String text) async {
    final client = ref.read(voxonClientProvider);
    if (client == null) return;
    try {
      final result = await client.call('customers.list', {
        'search': text,
        'limit': 8,
      });
      if (mounted) {
        setState(
          () => _customers = (result! as List).cast<Map<String, dynamic>>(),
        );
      }
    } on BackendException catch (error) {
      if (mounted) _showError(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(cashSessionProvider);

    return session.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (current) {
        if (current == null) return _openCashForm(l10n);
        final state = ref.watch(sellControllerProvider);
        if (state.lastSale != null) return _receipt(l10n, state.lastSale!);
        return _sale(l10n, state);
      },
    );
  }

  Widget _openCashForm(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.cashOpenTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l10n.cashOpenHint),
        const SizedBox(height: 12),
        TextField(
          controller: _openingFloat,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'RD\$0.00',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _openCash,
          child: Text(l10n.cashOpenTitle),
        ),
      ],
    );
  }

  Widget _receipt(AppLocalizations l10n, Map<String, dynamic> sale) {
    final theme = Theme.of(context);
    final change = sale['changeCents'] as int? ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.sellCharged(sale['number'] as int),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _TotalRow(
          label: l10n.sellTotal,
          cents: sale['totalCents'] as int,
          emphasized: true,
        ),
        if (change > 0)
          Text(
            l10n.sellChange(formatMoney(change)),
            style: theme.textTheme.titleMedium,
          ),
        for (final payment
            in (sale['payments'] as List).cast<Map<String, dynamic>>())
          Text(
            '${paymentLabel(l10n, payment['method'] as String)}: ${formatMoney(payment['amountCents'] as int)}',
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () =>
              ref.read(sellControllerProvider.notifier).startNewSale(),
          child: Text(l10n.sellNewSale),
        ),
      ],
    );
  }

  Widget _sale(AppLocalizations l10n, SellState state) {
    final theme = Theme.of(context);
    final controller = ref.read(sellControllerProvider.notifier);
    final quote = state.quote;
    final quoteLines = (quote?['lines'] as List?)?.cast<Map<String, dynamic>>();
    final total = state.totalCents;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.sellCurrentSale, style: theme.textTheme.titleLarge),
        if (state.cart.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l10n.sellEmptyCart, textAlign: TextAlign.center),
          ),
        for (final (index, line) in state.cart.lines.indexed)
          _CartLineTile(
            key: ValueKey('${line.productId}:${line.quantityMilli}'),
            line: line,
            amountCents: quoteLines != null && index < quoteLines.length
                ? quoteLines[index]['netCents'] as int
                : line.estimatedCents,
            onQuantity: (milli) {
              try {
                controller.setQuantity(line.productId, milli);
              } on CartException catch (error) {
                _showError(context, cartErrorLabel(l10n, error));
              }
            },
            onRemove: () => controller.remove(line.productId),
          ),
        if (state.quoteError != null)
          Text(
            state.quoteError!,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (quote != null) ...[
          const Divider(),
          _TotalRow(
            label: l10n.sellSubtotal,
            cents: quote['subtotalCents'] as int,
          ),
          _TotalRow(label: l10n.sellTax, cents: quote['taxCents'] as int),
          if ((quote['tipCents'] as int) > 0)
            _TotalRow(label: l10n.sellTip, cents: quote['tipCents'] as int),
          _TotalRow(label: l10n.sellTotal, cents: total!, emphasized: true),
        ],
        if (!state.cart.isEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final method in ['cash', 'card', 'transfer', 'credit'])
                ChoiceChip(
                  label: Text(paymentLabel(l10n, method)),
                  selected: state.method == method,
                  onSelected: (_) => controller.selectMethod(method),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.method == 'cash') ..._cashFields(l10n, total),
          if (state.method == 'credit') ..._customerFields(l10n, state),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || total == null ? null : _charge,
            child: Text(
              total == null
                  ? l10n.sellTotal
                  : l10n.sellCharge(formatMoney(total)),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _cashFields(AppLocalizations l10n, int? total) {
    final received = parseMoney(_received.text);
    String? note;
    if (total != null && received != null) {
      note = received >= total
          ? l10n.sellChange(formatMoney(received - total))
          : l10n.sellMissing(formatMoney(total - received));
    }
    return [
      TextField(
        controller: _received,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: l10n.sellReceived,
          hintText: total == null ? null : formatMoney(total),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(note, style: Theme.of(context).textTheme.titleMedium),
        ),
    ];
  }

  List<Widget> _customerFields(AppLocalizations l10n, SellState state) {
    final controller = ref.read(sellControllerProvider.notifier);
    final customer = state.customer;
    if (customer != null) {
      return [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(
            l10n.sellCreditTo(
              customer.name,
              formatMoney(customer.availableCreditCents),
            ),
          ),
          trailing: TextButton(
            onPressed: () => controller.selectCustomer(null),
            child: Text(l10n.sellChangeCustomer),
          ),
        ),
      ];
    }
    return [
      TextField(
        controller: _customerSearch,
        decoration: InputDecoration(
          labelText: l10n.sellCustomerSearch,
          prefixIcon: const Icon(Icons.person_search),
          border: const OutlineInputBorder(),
        ),
        onChanged: _searchCustomers,
      ),
      for (final json in _customers)
        ListTile(
          title: Text(json['name'] as String),
          subtitle: Text(formatMoney(json['availableCreditCents'] as int)),
          onTap: () => controller.selectCustomer(CreditCustomer.fromJson(json)),
        ),
    ];
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    super.key,
    required this.line,
    required this.amountCents,
    required this.onQuantity,
    required this.onRemove,
  });

  final CartLine line;
  final int amountCents;
  final ValueChanged<int> onQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: Theme.of(context).textTheme.titleSmall),
                Text(formatMoney(amountCents)),
              ],
            ),
          ),
          if (line.allowsFraction)
            SizedBox(
              width: 96,
              child: TextFormField(
                initialValue: formatQuantity(line.quantityMilli),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  suffixText: unitLabel(line.unit),
                  isDense: true,
                ),
                onFieldSubmitted: (text) {
                  final milli = parseQuantity(text);
                  if (milli == null) {
                    _showError(context, l10n.sellInvalidQuantity);
                  } else {
                    onQuantity(milli);
                  }
                },
              ),
            )
          else ...[
            IconButton(
              onPressed: () => onQuantity(line.quantityMilli - 1000),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(formatQuantity(line.quantityMilli)),
            IconButton(
              onPressed: () => onQuantity(line.quantityMilli + 1000),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
          IconButton(
            tooltip: l10n.sellRemove,
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
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
