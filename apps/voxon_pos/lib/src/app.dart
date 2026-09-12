import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon_pos/src/pos_controller.dart';
import 'package:voxon_pos/src/screens/link_screen.dart';
import 'package:voxon_pos/src/screens/pos_home_screen.dart';
import 'package:voxon_pos/src/screens/staff_login_screen.dart';

/// VOXON POS: toma el nombre, el color y el logo del negocio al que está vinculada.
class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(posControllerProvider);
    final branding = switch (state) {
      PosLinked(:final link) =>
        ref.watch(brandingProvider(link.instanceId)).value ??
            Branding(
              displayName: link.instanceName,
              primaryColorHex: Branding.voxon.primaryColorHex,
            ),
      _ => Branding.voxon,
    };

    return MaterialApp(
      title: branding.displayName,
      debugShowCheckedModeBanner: false,
      theme: BrandTheme.light(branding),
      darkTheme: BrandTheme.dark(branding),
      home: switch (state) {
        PosLoading() => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        PosUnlinked() => const LinkScreen(),
        PosLinked(:final link, session: null) => StaffLoginScreen(link: link),
        PosLinked(:final link, :final session?) => PosHomeScreen(
          link: link,
          session: session,
        ),
      },
    );
  }
}
