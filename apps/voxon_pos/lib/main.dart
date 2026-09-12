import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon_pos/src/app.dart';
import 'package:voxon_pos/src/link_store.dart';
import 'package:voxon_pos/src/pos_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VoxonFirebase.initialize();
  runApp(
    ProviderScope(
      overrides: [
        deviceLinkServiceProvider.overrideWithValue(
          FirebaseDeviceLinkService(),
        ),
        posSessionServiceProvider.overrideWithValue(
          FirebasePosSessionService(),
        ),
        linkStoreProvider.overrideWithValue(PreferencesLinkStore()),
      ],
      child: const PosApp(),
    ),
  );
}
