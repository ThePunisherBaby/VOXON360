/// Productos enviados a preparación, agrupados por orden.
class KitchenOrder {
  const KitchenOrder({
    required this.orderId,
    required this.orderNumber,
    required this.orderKind,
    required this.tableName,
    required this.oldestSentAt,
    required this.items,
  });

  final String orderId;
  final int orderNumber;

  /// dine_in, takeout o delivery.
  final String orderKind;
  final String? tableName;
  final DateTime? oldestSentAt;

  /// Filas de restaurant.kitchen.queue.
  final List<Map<String, dynamic>> items;
}

/// Agrupa la cola por orden, empezando por la que lleva más tiempo esperando.
List<KitchenOrder> groupKitchenQueue(List<Map<String, dynamic>> items) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final item in items) {
    grouped.putIfAbsent(item['orderId'] as String, () => []).add(item);
  }
  final orders = [
    for (final entry in grouped.entries)
      KitchenOrder(
        orderId: entry.key,
        orderNumber: entry.value.first['orderNumber'] as int,
        orderKind: entry.value.first['orderKind'] as String,
        tableName: entry.value.first['tableName'] as String?,
        oldestSentAt: _oldest(entry.value),
        items: entry.value,
      ),
  ];
  orders.sort((a, b) {
    final byTime = (a.oldestSentAt ?? DateTime(9999)).compareTo(
      b.oldestSentAt ?? DateTime(9999),
    );
    return byTime != 0 ? byTime : a.orderNumber.compareTo(b.orderNumber);
  });
  return orders;
}

DateTime? _oldest(List<Map<String, dynamic>> items) {
  DateTime? oldest;
  for (final item in items) {
    final sentAt = DateTime.tryParse(item['sentAt'] as String? ?? '');
    if (sentAt != null && (oldest == null || sentAt.isBefore(oldest))) {
      oldest = sentAt;
    }
  }
  return oldest;
}

/// Estados a los que puede pasar un producto; el motor no permite retroceder.
List<String> nextKitchenActions(String status) => switch (status) {
  'sent' => const ['preparing', 'ready'],
  'preparing' => const ['ready'],
  'ready' => const ['served'],
  _ => const [],
};

/// Minutos enteros de espera.
int minutesWaiting(DateTime? since, DateTime now) {
  if (since == null) return 0;
  final minutes = now.difference(since).inMinutes;
  return minutes < 0 ? 0 : minutes;
}
