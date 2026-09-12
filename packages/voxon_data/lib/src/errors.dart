import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Error con un código estable y un mensaje listo para mostrar.
class VoxonException implements Exception {
  const VoxonException(this.code, this.message);

  /// Código de Firebase, como `permission-denied` o `failed-precondition`.
  final String code;
  final String message;

  bool get isOffline =>
      code == 'unavailable' || code == 'network-request-failed';

  @override
  String toString() => message;
}

/// Ejecuta [action] y convierte los errores de Firebase en [VoxonException].
Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on FirebaseFunctionsException catch (error) {
    throw VoxonException(error.code, error.message ?? 'No se pudo completar');
  } on FirebaseAuthException catch (error) {
    throw VoxonException(error.code, authMessage(error.code));
  } on FirebaseException catch (error) {
    throw VoxonException(
      error.code,
      error.code == 'permission-denied'
          ? 'No tienes permiso para eso'
          : error.message ?? 'Error de Firebase',
    );
  }
}

/// Mensajes en español para los errores de Firebase Auth.
String authMessage(String code) => switch (code) {
  'invalid-email' => 'El correo no es válido',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'Correo o contraseña incorrectos',
  'email-already-in-use' => 'Ese correo ya tiene una cuenta',
  'weak-password' => 'La contraseña debe tener al menos 6 caracteres',
  'network-request-failed' => 'Sin internet',
  'too-many-requests' => 'Demasiados intentos; espera un momento',
  'operation-not-allowed' => 'Ese método de entrada no está activado',
  _ => 'No se pudo completar ($code)',
};
