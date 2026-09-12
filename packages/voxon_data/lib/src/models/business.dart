import 'package:voxon_domain/voxon_domain.dart';

import 'package:voxon_data/src/models/pairing.dart';

/// Puestos dentro de una instancia. `locked` es una caja sin empleado adentro.
enum StaffRole {
  owner,
  manager,
  cashier,
  waiter,
  kitchen,
  locked;

  static StaffRole parse(String? value) => StaffRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => StaffRole.locked,
  );

  /// Puestos que se le pueden dar a un empleado.
  static const assignable = [owner, manager, cashier, waiter, kitchen];

  String get label => switch (this) {
    owner => 'Dueño',
    manager => 'Gerente',
    cashier => 'Cajero',
    waiter => 'Mesero',
    kitchen => 'Cocina',
    locked => 'Sin empleado',
  };

  bool get canSell => this == owner || this == manager || this == cashier;

  bool get canManage => this == owner || this == manager;
}

/// Marca del negocio que toman las cajas: nombre, color, logo y pie del ticket.
final class Branding {
  const Branding({
    required this.displayName,
    required this.primaryColorHex,
    this.logoDataUrl,
    this.receiptFooter,
  });

  factory Branding.fromMap(
    Map<String, dynamic>? data, {
    String fallbackName = 'VOXON POS',
  }) => Branding(
    displayName: data?['displayName'] as String? ?? fallbackName,
    primaryColorHex: data?['primaryColor'] as String? ?? voxon.primaryColorHex,
    logoDataUrl: data?['logoDataUrl'] as String?,
    receiptFooter: data?['receiptFooter'] as String?,
  );

  /// La marca de VOXON, para una caja todavía sin vincular.
  static const voxon = Branding(
    displayName: 'VOXON POS',
    primaryColorHex: '#1B5E20',
  );

  final String displayName;
  final String primaryColorHex;

  /// Logo como `data:image/png;base64,…`.
  final String? logoDataUrl;
  final String? receiptFooter;

  int get primaryColorValue {
    try {
      return parseHexColor(primaryColorHex);
    } on FormatException {
      return parseHexColor(voxon.primaryColorHex);
    }
  }

  Map<String, Object?> toMap() => {
    'displayName': displayName,
    'primaryColor': primaryColorHex,
    'logoDataUrl': logoDataUrl,
    'receiptFooter': receiptFooter,
  };
}

/// Datos de una instancia que necesitan las apps.
final class InstanceSummary {
  const InstanceSummary({
    required this.id,
    required this.name,
    required this.mode,
    required this.accountId,
    required this.modules,
    required this.priceMode,
    required this.legalTip,
    required this.active,
  });

  factory InstanceSummary.fromMap(String id, Map<String, dynamic> data) {
    final fiscal = data['fiscal'] as Map<String, dynamic>? ?? const {};
    return InstanceSummary(
      id: id,
      name: data['name'] as String? ?? '',
      mode: data['mode'] as String? ?? '',
      accountId: data['accountId'] as String? ?? '',
      modules: Set.unmodifiable(
        (data['modules'] as List? ?? const []).cast<String>(),
      ),
      priceMode: fiscal['priceMode'] == 'tax_excluded'
          ? PriceMode.taxExcluded
          : PriceMode.taxIncluded,
      legalTip: fiscal['legalTip'] == true,
      active: data['active'] == true,
    );
  }

  final String id;
  final String name;
  final String mode;
  final String accountId;
  final Set<String> modules;
  final PriceMode priceMode;
  final bool legalTip;
  final bool active;

  bool uses(String module) => modules.contains(module);

  BusinessMode? get businessMode => ModeCatalog.standard.byId(mode);
}

/// Empleado de la instancia (el PIN nunca llega a las apps).
final class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
  });

  factory StaffMember.fromMap(String id, Map<String, dynamic> data) =>
      StaffMember(
        id: id,
        name: data['name'] as String? ?? '',
        role: StaffRole.parse(data['role'] as String?),
        active: data['active'] == true,
      );

  final String id;
  final String name;
  final StaffRole role;
  final bool active;

  /// Iniciales para el botón del empleado: "Luis Pérez" → "LP".
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

/// Empleado con sesión abierta en la caja.
final class StaffSession {
  const StaffSession({
    required this.staffId,
    required this.name,
    required this.role,
  });

  factory StaffSession.fromMap(Map<String, dynamic> data) => StaffSession(
    staffId: data['staffId'] as String,
    name: data['name'] as String,
    role: StaffRole.parse(data['role'] as String?),
  );

  final String staffId;
  final String name;
  final StaffRole role;
}

/// Caja con VOXON POS vista desde VOXON 360.
final class DeviceInfo {
  const DeviceInfo({
    required this.uid,
    required this.name,
    required this.platform,
    required this.number,
    required this.status,
    this.enrolledWith,
    this.lastSeenAt,
  });

  factory DeviceInfo.fromMap(String uid, Map<String, dynamic> data) =>
      DeviceInfo(
        uid: uid,
        name: data['name'] as String? ?? 'Caja',
        platform: data['platform'] as String? ?? '',
        number: (data['number'] as num?)?.toInt() ?? 0,
        status: data['status'] as String? ?? 'revoked',
        enrolledWith: data['enrolledWith'] as String?,
        lastSeenAt: readDate(data['lastSeenAt']),
      );

  final String uid;
  final String name;
  final String platform;
  final int number;

  /// `active` o `revoked`.
  final String status;

  /// `qr` o `code`.
  final String? enrolledWith;
  final DateTime? lastSeenAt;

  bool get isActive => status == 'active';
}

/// Cuenta y primer negocio recién creados.
final class CreatedAccount {
  const CreatedAccount({required this.accountId, required this.instanceId});

  factory CreatedAccount.fromMap(Map<String, dynamic> data) => CreatedAccount(
    accountId: data['accountId'] as String,
    instanceId: data['instanceId'] as String,
  );

  final String accountId;
  final String instanceId;
}
