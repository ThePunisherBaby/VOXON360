import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon360/src/app.dart';
import 'package:voxon360/src/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VoxonFirebase.initialize();
  runApp(
    ProviderScope(
      overrides: [
        accountAuthServiceProvider.overrideWithValue(
          FirebaseAccountAuthService(),
        ),
        adminServiceProvider.overrideWithValue(FirebaseAdminService()),
      ],
      child: const Voxon360App(),
    ),
  );
}
