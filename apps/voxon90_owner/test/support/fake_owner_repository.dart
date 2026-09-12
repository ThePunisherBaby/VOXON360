import 'dart:async';

import 'package:voxon90_owner/data/owner_repository.dart';

/// Repositorio de mentira con los datos que subiría una caja principal.
class FakeOwnerRepository implements OwnerRepository {
  FakeOwnerRepository({this.linkCode = 'ABCD2345'});

  final String linkCode;
  final _users = StreamController<String?>.broadcast();
  final _devices = StreamController<List<LinkedDevice>>.broadcast();

  String? _uid;
  List<LinkedDevice> _deviceList = const [
    LinkedDevice(uid: 'caja', name: 'Caja principal'),
  ];

  /// Códigos creados, para revisarlos en las pruebas.
  final createdCodes = <String>[];

  static final status = <String, dynamic>{
    'businessName': 'Colmado La Esquina',
    'businessType': 'colmado',
    'day': '2026-09-11',
    'todaySales': {'count': 2, 'totalCents': 23600, 'taxCents': 3600},
    'openCashSession': {'expectedCashCents': 111800, 'openedByName': 'Luis'},
    'openOrders': 0,
    'lowStockCount': 1,
    'receivablesCents': 5900,
    'syncedAt': DateTime(2026, 9, 11, 15, 4),
  };

  static final today = <String, dynamic>{
    'day': '2026-09-11',
    'sales': {'count': 2, 'totalCents': 23600, 'taxCents': 3600},
    'voided': {'count': 0, 'totalCents': 0},
    'payments': [
      {'method': 'cash', 'amountCents': 17700},
      {'method': 'credit', 'amountCents': 5900},
    ],
    'topProducts': [
      {
        'description': 'Presidente 650 ml',
        'quantityMilli': 2000,
        'netCents': 20000,
      },
    ],
    'recentSales': [
      {
        'number': 2,
        'status': 'completed',
        'totalCents': 5900,
        'cashierName': 'Luis',
        'customerName': 'Juan',
      },
      {
        'number': 1,
        'status': 'completed',
        'totalCents': 17700,
        'cashierName': 'Luis',
      },
    ],
  };

  @override
  String? get currentUserId => _uid;

  @override
  Stream<String?> userChanges() async* {
    yield _uid;
    yield* _users.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    _uid = 'dueno';
    _users.add(_uid);
  }

  @override
  Future<void> register(String email, String password) =>
      signIn(email, password);

  @override
  Future<void> signOut() async {
    _uid = null;
    _users.add(null);
  }

  @override
  Stream<List<Business>> businesses() => Stream.value(const [
    Business(id: 'negocio1', name: 'Colmado La Esquina'),
  ]);

  @override
  Future<Business> createBusiness(String name) async =>
      Business(id: 'negocio2', name: name);

  @override
  Stream<Map<String, dynamic>?> document(String businessId, String path) =>
      Stream.value(switch (path) {
        'snapshots/status' => status,
        'snapshots/inventory' => {
          'lowStock': [
            {
              'name': 'Refresco',
              'stockMilli': 3000,
              'minStockMilli': 5000,
              'unit': 'unit',
            },
          ],
        },
        'snapshots/receivables' => {
          'totalCents': 5900,
          'customers': [
            {'name': 'Juan', 'phone': '8095551234', 'balanceCents': 5900},
          ],
        },
        'snapshots/cash' => {
          'sessions': [
            {
              'openedByName': 'Luis',
              'closedAt': null,
              'expectedCashCents': 111800,
              'differenceCents': null,
            },
          ],
        },
        _ => null,
      });

  @override
  Stream<List<Map<String, dynamic>>> days(
    String businessId, {
    int limit = 14,
  }) => Stream.value([today]);

  @override
  Stream<List<LinkedDevice>> devices(String businessId) async* {
    yield _deviceList;
    yield* _devices.stream;
  }

  @override
  Future<void> removeDevice(String businessId, String deviceUid) async {
    _deviceList = [
      for (final device in _deviceList)
        if (device.uid != deviceUid) device,
    ];
    _devices.add(_deviceList);
  }

  @override
  Future<LinkCode> createLinkCode(String businessId) async {
    createdCodes.add(linkCode);
    return LinkCode(
      code: linkCode,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }
}
