import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90_owner/app.dart';
import 'package:voxon90_owner/data/firebase_owner_repository.dart';
import 'package:voxon90_owner/firebase_config.dart';
import 'package:voxon90_owner/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!FirebaseConfig.isComplete) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Firebase.initializeApp(options: FirebaseConfig.options);
  if (FirebaseConfig.emulatorHost.isNotEmpty) {
    await FirebaseAuth.instance.useAuthEmulator(
      FirebaseConfig.emulatorHost,
      9099,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      FirebaseConfig.emulatorHost,
      8080,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        ownerRepositoryProvider.overrideWithValue(
          FirebaseOwnerRepository(
            FirebaseAuth.instance,
            FirebaseFirestore.instance,
          ),
        ),
      ],
      child: const OwnerApp(),
    ),
  );
}

/// Sin los datos del proyecto la app no puede hablar con Firebase.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VOXON90 Dueño',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Falta configurar el proyecto de Firebase',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Compila con --dart-define=FIREBASE_PROJECT_ID, FIREBASE_API_KEY, '
                  'FIREBASE_APP_ID y FIREBASE_SENDER_ID. Ver apps/voxon90_owner/README.md.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
