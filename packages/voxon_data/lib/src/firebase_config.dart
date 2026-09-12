import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Proyecto de Firebase de VOXON.
///
/// Los datos de la app web son públicos por diseño: la seguridad está en las
/// reglas de Firestore y en las Cloud Functions. Se pueden cambiar al compilar:
/// `--dart-define=FIREBASE_PROJECT_ID=...` y compañía, o apuntar a los
/// emuladores con `--dart-define=FIREBASE_EMULATOR=127.0.0.1`.
abstract final class VoxonFirebase {
  static const region = 'us-central1';

  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'voxon360-8349a',
  );
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyBN_jRMS7TP2CqdD0MypqNFQYWSzfF-1ng',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:855655113107:web:220e1301b748d4aa220866',
  );
  static const senderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '855655113107',
  );
  static const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR');

  static const options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    storageBucket: '$projectId.firebasestorage.app',
  );

  static bool get usesEmulator => emulatorHost.isNotEmpty;

  /// Arranca Firebase y, si se pidió, conecta con los emuladores.
  static Future<void> initialize() async {
    await Firebase.initializeApp(options: options);
    if (usesEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      functions.useFunctionsEmulator(emulatorHost, 5001);
    }
  }

  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: region);
}
