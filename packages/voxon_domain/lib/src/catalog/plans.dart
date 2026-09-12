import 'dart:convert';

import 'package:voxon_domain/src/catalog/catalog_data.g.dart';

/// Los grados de VOXON como planes de suscripción.
enum PlanTier {
  v45,
  v90,
  v180,
  v360;

  static PlanTier? tryParse(String? value) {
    for (final tier in values) {
      if (tier.name == value) return tier;
    }
    return null;
  }

  /// 45, 90, 180 o 360.
  int get degrees => int.parse(name.substring(1));
}

/// Topes de un plan. `0` significa sin tope.
final class PlanLimits {
  const PlanLimits({
    required this.instances,
    required this.users,
    required this.products,
    required this.devices,
  });

  factory PlanLimits.fromJson(Map<String, dynamic> json) => PlanLimits(
    instances: json['instances'] as int,
    users: json['users'] as int,
    products: json['products'] as int,
    devices: json['devices'] as int,
  );

  final int instances;

  /// Personas con cuenta y empleados con PIN.
  final int users;
  final int products;

  /// Cajas con VOXON POS.
  final int devices;

  /// Si caben [used] con este [limit].
  static bool allows(int used, int limit) => limit == 0 || used <= limit;
}

final class Plan {
  const Plan({
    required this.tier,
    required this.name,
    required this.tagline,
    required this.priceMonthly,
    required this.limits,
    required this.features,
  });

  factory Plan.fromJson(PlanTier tier, Map<String, dynamic> json) => Plan(
    tier: tier,
    name: json['name'] as String,
    tagline: json['tagline'] as String,
    priceMonthly: json['priceMonthly'] as int,
    limits: PlanLimits.fromJson(json['limits'] as Map<String, dynamic>),
    features: Set.unmodifiable((json['features'] as List).cast<String>()),
  );

  final PlanTier tier;
  final String name;
  final String tagline;

  /// Precio mensual en la moneda del catálogo (provisional).
  final int priceMonthly;
  final PlanLimits limits;
  final Set<String> features;

  bool has(String feature) => features.contains(feature);
}

final class PlanCatalog {
  const PlanCatalog._({
    required this.currency,
    required this.trialDays,
    required this.trialTier,
    required this.featureNames,
    required this.plans,
  });

  factory PlanCatalog.fromJson(Map<String, dynamic> json) {
    final tiers = json['tiers'] as Map<String, dynamic>;
    return PlanCatalog._(
      currency: json['currency'] as String,
      trialDays: json['trialDays'] as int,
      trialTier:
          PlanTier.tryParse(json['trialTier'] as String?) ?? PlanTier.v45,
      featureNames: Map.unmodifiable(
        (json['features'] as Map).cast<String, String>(),
      ),
      plans: Map.unmodifiable({
        for (final tier in PlanTier.values)
          tier: Plan.fromJson(tier, tiers[tier.name] as Map<String, dynamic>),
      }),
    );
  }

  /// El catálogo de shared/plans.json incluido en el paquete.
  static final standard = PlanCatalog.fromJson(
    jsonDecode(plansJson) as Map<String, dynamic>,
  );

  final String currency;
  final int trialDays;

  /// Plan con el que arranca la prueba gratis.
  final PlanTier trialTier;
  final Map<String, String> featureNames;
  final Map<PlanTier, Plan> plans;

  Plan of(PlanTier tier) => plans[tier]!;

  /// El plan más bajo que trae [feature], para decir «desde el plan 90».
  PlanTier? lowestWith(String feature) {
    for (final tier in PlanTier.values) {
      if (of(tier).has(feature)) return tier;
    }
    return null;
  }
}
