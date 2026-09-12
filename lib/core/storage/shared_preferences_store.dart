import 'package:shared_preferences/shared_preferences.dart';

import 'package:voxon90/core/storage/key_value_store.dart';

/// [KeyValueStore] respaldado por `shared_preferences`: SharedPreferences en
/// Android, NSUserDefaults en macOS y un archivo JSON en Linux y Windows.
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore._(this._prefs);

  static Future<SharedPreferencesStore> create() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    return SharedPreferencesStore._(prefs);
  }

  final SharedPreferencesWithCache _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
