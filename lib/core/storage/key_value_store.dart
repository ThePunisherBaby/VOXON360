/// Almacenamiento clave-valor para ajustes simples.
///
/// La app depende de esta interfaz y no del plugin concreto, para poder
/// cambiar la implementación o usar [InMemoryKeyValueStore] en los tests.
abstract interface class KeyValueStore {
  String? getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

/// Implementación en memoria, pensada para tests.
class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, String>? initialValues])
    : _values = {...?initialValues};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
