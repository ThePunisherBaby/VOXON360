import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/features/sell/domain/cart.dart';

/// Cliente elegido para vender fiado.
class CreditCustomer {
  const CreditCustomer({
    required this.id,
    required this.name,
    required this.availableCreditCents,
  });

  factory CreditCustomer.fromJson(Map<String, dynamic> json) => CreditCustomer(
    id: json['id'] as String,
    name: json['name'] as String,
    availableCreditCents: json['availableCreditCents'] as int? ?? 0,
  );

  final String id;
  final String name;
  final int availableCreditCents;
}

class SellState {
  const SellState({
    this.cart = const Cart(),
    this.quote,
    this.quoteError,
    this.method = 'cash',
    this.customer,
    this.lastSale,
  });

  final Cart cart;

  /// Resultado de sales.quote para el carrito actual.
  final Map<String, dynamic>? quote;
  final String? quoteError;

  /// cash, card, transfer o credit.
  final String method;
  final CreditCustomer? customer;

  /// Venta recién cobrada, para mostrar el recibo.
  final Map<String, dynamic>? lastSale;

  int? get totalCents => quote?['totalCents'] as int?;
}

/// Venta en curso. Se conserva al cambiar de sección.
final sellControllerProvider = NotifierProvider<SellController, SellState>(
  SellController.new,
);

class SellController extends Notifier<SellState> {
  Timer? _quoteTimer;
  int _quoteSequence = 0;

  @override
  SellState build() {
    ref.onDispose(() => _quoteTimer?.cancel());
    return const SellState();
  }

  void add(Map<String, dynamic> product) =>
      _updateCart(state.cart.add(product));

  void setQuantity(String productId, int quantityMilli) =>
      _updateCart(state.cart.setQuantity(productId, quantityMilli));

  void remove(String productId) => _updateCart(state.cart.remove(productId));

  void selectMethod(String method) => state = SellState(
    cart: state.cart,
    quote: state.quote,
    quoteError: state.quoteError,
    method: method,
    customer: state.customer,
  );

  void selectCustomer(CreditCustomer? customer) => state = SellState(
    cart: state.cart,
    quote: state.quote,
    quoteError: state.quoteError,
    method: state.method,
    customer: customer,
  );

  void startNewSale() => state = const SellState();

  /// Cobra la venta con la forma de pago elegida. En efectivo, `receivedCents`
  /// es lo que entregó el cliente (null = el total exacto).
  Future<Map<String, dynamic>> charge({int? receivedCents}) async {
    final total = state.totalCents;
    final client = ref.read(voxonClientProvider);
    if (total == null || client == null) {
      throw const BackendException(
        'invalid_request',
        'La venta aún no tiene total',
      );
    }

    final List<Map<String, Object?>> payments;
    if (state.method == 'cash') {
      final received = receivedCents ?? total;
      if (received < total) throw const CartException('insufficient_cash');
      payments = [
        {'method': 'cash', 'amountCents': received},
      ];
    } else {
      if (state.method == 'credit' && state.customer == null) {
        throw const CartException('customer_required');
      }
      payments = total == 0
          ? const []
          : [
              {'method': state.method, 'amountCents': total},
            ];
    }

    final sale =
        await client.call('sales.complete', {
              'lines': state.cart.toSaleLines(),
              'payments': payments,
              if (state.method == 'credit') 'customerId': state.customer!.id,
            })
            as Map<String, dynamic>;
    _quoteTimer?.cancel();
    state = SellState(lastSale: sale);
    return sale;
  }

  void _updateCart(Cart cart) {
    state = SellState(
      cart: cart,
      quote: state.quote,
      method: state.method,
      customer: state.customer,
    );
    _scheduleQuote();
  }

  void _scheduleQuote() {
    _quoteTimer?.cancel();
    final sequence = ++_quoteSequence;
    if (state.cart.isEmpty) {
      state = SellState(method: state.method, customer: state.customer);
      return;
    }
    _quoteTimer = Timer(
      const Duration(milliseconds: 250),
      () => _quote(sequence),
    );
  }

  // Solo la cotización más reciente actualiza la pantalla.
  Future<void> _quote(int sequence) async {
    final client = ref.read(voxonClientProvider);
    if (client == null) return;
    final cart = state.cart;
    try {
      final quote =
          await client.call('sales.quote', {'lines': cart.toSaleLines()})
              as Map<String, dynamic>;
      if (sequence == _quoteSequence) {
        state = SellState(
          cart: state.cart,
          quote: quote,
          method: state.method,
          customer: state.customer,
        );
      }
    } on BackendException catch (error) {
      if (sequence == _quoteSequence) {
        state = SellState(
          cart: state.cart,
          quoteError: error.message,
          method: state.method,
          customer: state.customer,
        );
      }
    }
  }
}
