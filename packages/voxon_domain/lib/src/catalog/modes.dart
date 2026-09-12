import 'dart:convert';

import 'package:voxon_domain/src/catalog/catalog_data.g.dart';
import 'package:voxon_domain/src/sale_calculator.dart';

/// Si un modo se puede elegir al crear una instancia.
enum ModeStatus {
  /// Los primeros en construirse: supermercado, colmado, restaurante y tienda.
  priority,

  /// Terminado.
  ready,

  /// Configurado, pero todavía no disponible.
  planned;

  static ModeStatus parse(String value) => ModeStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ModeStatus.planned,
  );
}

/// Un modo de negocio: qué módulos enciende y con qué reglas nace la instancia.
final class BusinessMode {
  const BusinessMode({
    required this.id,
    required this.order,
    required this.status,
    required this.name,
    required this.description,
    required this.icon,
    required this.colorHex,
    required this.priceMode,
    required this.legalTip,
    required this.modules,
    required this.categories,
    this.stations = const [],
  });

  factory BusinessMode.fromJson(Map<String, dynamic> json) => BusinessMode(
    id: json['id'] as String,
    order: json['order'] as int,
    status: ModeStatus.parse(json['status'] as String),
    name: json['name'] as String,
    description: json['description'] as String,
    icon: json['icon'] as String,
    colorHex: json['color'] as String,
    priceMode: json['priceMode'] == 'tax_excluded'
        ? PriceMode.taxExcluded
        : PriceMode.taxIncluded,
    legalTip: json['legalTip'] as bool,
    modules: List.unmodifiable((json['modules'] as List).cast<String>()),
    categories: List.unmodifiable((json['categories'] as List).cast<String>()),
    stations: List.unmodifiable(
      (json['stations'] as List? ?? const []).cast<String>(),
    ),
  );

  final String id;
  final int order;
  final ModeStatus status;
  final String name;
  final String description;

  /// Nombre de un ícono de Material, como `restaurant`.
  final String icon;

  /// Color de marca por defecto, como `#C62828`.
  final String colorHex;
  final PriceMode priceMode;
  final bool legalTip;
  final List<String> modules;
  final List<String> categories;

  /// Estaciones de preparación (cocina, bar) para los modos con comandas.
  final List<String> stations;

  bool get isAvailable => status != ModeStatus.planned;

  bool uses(String module) => modules.contains(module);

  /// Color como entero ARGB (0xFFRRGGBB).
  int get colorValue => parseHexColor(colorHex);
}

/// `#C62828` o `C62828` → `0xFFC62828`; `#80C62828` respeta la transparencia.
int parseHexColor(String hex) {
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(digits)) {
    throw FormatException('Color inválido', hex);
  }
  return int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16);
}

/// Los modos de negocio de VOXON, en orden de trabajo.
final class ModeCatalog {
  const ModeCatalog._(this.modes, this.moduleNames);

  factory ModeCatalog.fromJson(Map<String, dynamic> json) {
    final modes = [
      for (final mode in json['modes'] as List)
        BusinessMode.fromJson(mode as Map<String, dynamic>),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return ModeCatalog._(
      List.unmodifiable(modes),
      Map.unmodifiable((json['modules'] as Map).cast<String, String>()),
    );
  }

  /// El catálogo de shared/modes.json incluido en el paquete.
  static final standard = ModeCatalog.fromJson(
    jsonDecode(modesJson) as Map<String, dynamic>,
  );

  final List<BusinessMode> modes;

  /// Módulo → descripción para mostrar.
  final Map<String, String> moduleNames;

  List<BusinessMode> get available => [
    for (final mode in modes)
      if (mode.isAvailable) mode,
  ];

  BusinessMode? byId(String id) {
    for (final mode in modes) {
      if (mode.id == id) return mode;
    }
    return null;
  }
}
