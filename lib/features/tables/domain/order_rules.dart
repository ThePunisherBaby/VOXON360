import 'package:voxon90/features/sell/domain/cart.dart';

/// Roles que pueden cobrar una cuenta (restaurant.orders.checkout).
const cashierRoles = {'owner', 'manager', 'cashier'};

/// Roles que administran mesas y cancelan lo que ya se envió a preparación.
const managerRoles = {'owner', 'manager'};

/// Productos de la orden (restaurant.orders.get) que no están cancelados.
List<Map<String, dynamic>> activeItems(Map<String, dynamic> order) => [
  for (final item
      in (order['items'] as List? ?? const []).cast<Map<String, dynamic>>())
    if (item['status'] != 'cancelled') item,
];

/// Cuántos productos esperan ser enviados a cocina o bar.
int pendingItemCount(Map<String, dynamic> order) =>
    activeItems(order).where((item) => item['status'] == 'pending').length;

/// Lo pendiente lo cancela cualquiera; lo enviado, solo el dueño o un gerente.
bool canCancelItem(String status, String role) => switch (status) {
  'pending' => true,
  'sent' || 'preparing' || 'ready' => managerRoles.contains(role),
  _ => false,
};

/// Órdenes abiertas sin mesa: para llevar y delivery.
List<Map<String, dynamic>> ordersWithoutTable(
  List<Map<String, dynamic>> orders,
) => [
  for (final order in orders)
    if (order['kind'] != 'dine_in') order,
];

/// Pagos para cobrar la cuenta. En efectivo, `receivedCents` es lo que entregó
/// el cliente (null = el total exacto) y el motor calcula el vuelto.
List<Map<String, Object>> checkoutPayments({
  required String method,
  required int totalCents,
  int? receivedCents,
}) {
  if (method == 'cash') {
    final received = receivedCents ?? totalCents;
    if (received < totalCents) throw const CartException('insufficient_cash');
    return received == 0
        ? const []
        : [
            {'method': 'cash', 'amountCents': received},
          ];
  }
  return totalCents == 0
      ? const []
      : [
          {'method': method, 'amountCents': totalCents},
        ];
}
