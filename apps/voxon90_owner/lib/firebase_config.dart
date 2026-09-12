import 'package:firebase_core/firebase_core.dart';

/// Datos del proyecto de Firebase. Se pasan al compilar para no guardarlos en el código:
///
/// ```bash
/// flutter run --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_API_KEY=... \
///             --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_SENDER_ID=...
/// ```
class FirebaseConfig {
  const FirebaseConfig._();

  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

  /// Equipo con los emuladores de Firebase, para desarrollo.
  static const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR');

  static bool get isComplete =>
      projectId.isNotEmpty &&
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: '$projectId.firebasestorage.app',
  );
}
