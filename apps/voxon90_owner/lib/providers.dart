import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90_owner/data/owner_repository.dart';

/// Se define en main.dart (Firebase) o en los tests (falso).
final ownerRepositoryProvider = Provider<OwnerRepository>(
  (ref) => throw UnimplementedError('Falta definir ownerRepositoryProvider'),
);

final userIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(ownerRepositoryProvider).userChanges(),
);

final businessesProvider = StreamProvider<List<Business>>((ref) {
  if (ref.watch(userIdProvider).value == null) return Stream.value(const []);
  return ref.watch(ownerRepositoryProvider).businesses();
});

/// Negocio que se está viendo. Al salir de la sesión vuelve a null.
final selectedBusinessProvider = NotifierProvider<SelectedBusiness, String?>(
  SelectedBusiness.new,
);

class SelectedBusiness extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(userIdProvider, (previous, next) {
      if (next.value == null) state = null;
    });
    return null;
  }

  void select(String? businessId) => state = businessId;
}

/// `snapshots/status`, `snapshots/cash`, `snapshots/inventory` o `snapshots/receivables`.
final snapshotProvider =
    StreamProvider.family<
      Map<String, dynamic>?,
      ({String businessId, String name})
    >(
      (ref, key) => ref
          .watch(ownerRepositoryProvider)
          .document(key.businessId, 'snapshots/${key.name}'),
    );

final daysProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, businessId) => ref.watch(ownerRepositoryProvider).days(businessId),
);

final devicesProvider = StreamProvider.family<List<LinkedDevice>, String>(
  (ref, businessId) => ref.watch(ownerRepositoryProvider).devices(businessId),
);
