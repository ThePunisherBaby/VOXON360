import 'package:voxon_data/src/errors.dart';
import 'package:voxon_data/src/firebase_config.dart';

/// Llama una Cloud Function de VOXON y devuelve su respuesta como mapa.
Future<Map<String, dynamic>> callFunction(
  String name, [
  Map<String, Object?> data = const {},
]) => guard(() async {
  final result = await VoxonFirebase.functions
      .httpsCallable(name)
      .call<Object?>(data);
  final value = result.data;
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
});
