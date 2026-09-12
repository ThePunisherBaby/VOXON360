import 'package:cloud_firestore/cloud_firestore.dart';

/// Pasos de la vinculación de una caja con QR y doble código.
enum PairingStatus {
  /// La caja muestra el QR y espera que lo escaneen.
  waiting,

  /// El celular escaneó: la caja debe escribir el código del celular.
  claimed,

  /// La caja confirmó: el celular debe escribir el código de la caja.
  deviceConfirmed,

  linked,
  failed,
  cancelled,
  expired;

  static PairingStatus parse(String? value) => switch (value) {
    'waiting' => waiting,
    'claimed' => claimed,
    'device_confirmed' => deviceConfirmed,
    'linked' => linked,
    'failed' => failed,
    'cancelled' => cancelled,
    _ => expired,
  };

  bool get isFinished =>
      this == linked || this == failed || this == cancelled || this == expired;
}

/// Lo que devuelve `startPairing`: el QR que muestra la caja.
final class PairingTicket {
  const PairingTicket({
    required this.pairingId,
    required this.qrToken,
    required this.qr,
    required this.expiresAt,
  });

  factory PairingTicket.fromMap(Map<String, dynamic> data) => PairingTicket(
    pairingId: data['pairingId'] as String,
    qrToken: data['qrToken'] as String,
    qr: data['qr'] as String,
    expiresAt: DateTime.parse(data['expiresAt'] as String),
  );

  final String pairingId;
  final String qrToken;

  /// Texto que va dentro del QR: `voxon://pair?p=…&t=…`.
  final String qr;
  final DateTime expiresAt;
}

/// Estado en vivo de una vinculación (documento pairings/{id}).
final class PairingState {
  const PairingState({
    required this.id,
    required this.status,
    this.instanceId,
    this.instanceName,
    this.deviceName,
    this.deviceNumber,
    this.expiresAt,
  });

  /// [now] permite marcar como vencida una vinculación sin terminar.
  factory PairingState.fromMap(
    String id,
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    if (data == null) {
      return PairingState(id: id, status: PairingStatus.expired);
    }
    final expiresAt = readDate(data['expiresAt']);
    var status = PairingStatus.parse(data['status'] as String?);
    if (!status.isFinished &&
        expiresAt != null &&
        expiresAt.isBefore(now ?? DateTime.now())) {
      status = PairingStatus.expired;
    }
    return PairingState(
      id: id,
      status: status,
      instanceId: data['instanceId'] as String?,
      instanceName: data['instanceName'] as String?,
      deviceName: data['deviceName'] as String?,
      deviceNumber: (data['deviceNumber'] as num?)?.toInt(),
      expiresAt: expiresAt,
    );
  }

  final String id;
  final PairingStatus status;

  /// Negocio al que va la caja, desde que el celular escaneó.
  final String? instanceId;
  final String? instanceName;
  final String? deviceName;

  /// Número de la caja dentro del negocio, cuando ya quedó vinculada.
  final int? deviceNumber;
  final DateTime? expiresAt;
}

/// Lo que recibe el celular al escanear: el código A para escribir en la caja.
final class ClaimedPairing {
  const ClaimedPairing({
    required this.mobileCode,
    required this.instanceName,
    required this.deviceName,
    required this.expiresAt,
  });

  factory ClaimedPairing.fromMap(Map<String, dynamic> data) => ClaimedPairing(
    mobileCode: data['mobileCode'] as String,
    instanceName: data['instanceName'] as String,
    deviceName: data['deviceName'] as String,
    expiresAt: DateTime.parse(data['expiresAt'] as String),
  );

  final String mobileCode;
  final String instanceName;
  final String deviceName;
  final DateTime expiresAt;
}

/// Caja ya vinculada a una instancia.
final class LinkedDevice {
  const LinkedDevice({
    required this.instanceId,
    required this.instanceName,
    required this.mode,
    required this.deviceName,
    required this.deviceNumber,
  });

  factory LinkedDevice.fromMap(Map<String, dynamic> data) => LinkedDevice(
    instanceId: data['instanceId'] as String,
    instanceName: data['instanceName'] as String,
    mode: data['mode'] as String,
    deviceName: data['deviceName'] as String,
    deviceNumber: (data['deviceNumber'] as num).toInt(),
  );

  final String instanceId;
  final String instanceName;
  final String mode;
  final String deviceName;

  /// Número de la caja dentro del negocio (1, 2, 3…); prefija sus ventas.
  final int deviceNumber;
}

/// Código escrito para vincular una caja sin celular.
final class DeviceCode {
  const DeviceCode({
    required this.code,
    required this.expiresAt,
    required this.instanceName,
    required this.deviceName,
  });

  factory DeviceCode.fromMap(Map<String, dynamic> data) => DeviceCode(
    code: data['code'] as String,
    expiresAt: DateTime.parse(data['expiresAt'] as String),
    instanceName: data['instanceName'] as String,
    deviceName: data['deviceName'] as String,
  );

  final String code;
  final DateTime expiresAt;
  final String instanceName;
  final String deviceName;

  /// `ABCD-2345`, más fácil de dictar.
  String get formatted => '${code.substring(0, 4)}-${code.substring(4)}';
}

/// Fecha desde Firestore (Timestamp), texto ISO o DateTime.
DateTime? readDate(Object? value) => switch (value) {
  Timestamp() => value.toDate(),
  DateTime() => value,
  String() => DateTime.tryParse(value),
  _ => null,
};
