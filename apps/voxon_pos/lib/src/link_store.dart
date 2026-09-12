import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxon_data/voxon_data.dart';

/// Negocio al que quedó vinculada esta caja.
final class LinkedInstance {
  const LinkedInstance({
    required this.instanceId,
    required this.instanceName,
    required this.deviceName,
    required this.deviceNumber,
  });

  factory LinkedInstance.fromLinkedDevice(LinkedDevice device) =>
      LinkedInstance(
        instanceId: device.instanceId,
        instanceName: device.instanceName,
        deviceName: device.deviceName,
        deviceNumber: device.deviceNumber,
      );

  final String instanceId;
  final String instanceName;
  final String deviceName;
  final int deviceNumber;
}

/// Recuerda el vínculo en este equipo, para no volver a vincular al reiniciar.
abstract interface class LinkStore {
  Future<LinkedInstance?> read();

  Future<void> save(LinkedInstance link);

  Future<void> clear();
}

class PreferencesLinkStore implements LinkStore {
  PreferencesLinkStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _instanceId = 'voxon_pos.link.instanceId';
  static const _instanceName = 'voxon_pos.link.instanceName';
  static const _deviceName = 'voxon_pos.link.deviceName';
  static const _deviceNumber = 'voxon_pos.link.deviceNumber';

  final SharedPreferencesAsync _preferences;

  @override
  Future<LinkedInstance?> read() async {
    final instanceId = await _preferences.getString(_instanceId);
    if (instanceId == null) return null;
    return LinkedInstance(
      instanceId: instanceId,
      instanceName: await _preferences.getString(_instanceName) ?? '',
      deviceName: await _preferences.getString(_deviceName) ?? 'Caja',
      deviceNumber: await _preferences.getInt(_deviceNumber) ?? 0,
    );
  }

  @override
  Future<void> save(LinkedInstance link) async {
    await _preferences.setString(_instanceName, link.instanceName);
    await _preferences.setString(_deviceName, link.deviceName);
    await _preferences.setInt(_deviceNumber, link.deviceNumber);
    // El id va de último: si algo falla antes, la caja no se cree vinculada.
    await _preferences.setString(_instanceId, link.instanceId);
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_instanceId);
    await _preferences.remove(_instanceName);
    await _preferences.remove(_deviceName);
    await _preferences.remove(_deviceNumber);
  }
}

/// Para pruebas.
class MemoryLinkStore implements LinkStore {
  MemoryLinkStore([this.link]);

  LinkedInstance? link;

  @override
  Future<LinkedInstance?> read() async => link;

  @override
  Future<void> save(LinkedInstance value) async => link = value;

  @override
  Future<void> clear() async => link = null;
}
