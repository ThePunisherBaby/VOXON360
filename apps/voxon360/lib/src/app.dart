import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_ui/voxon_ui.dart';

import 'package:voxon360/src/providers.dart';
import 'package:voxon360/src/screens/home_screen.dart';
import 'package:voxon360/src/screens/onboarding_screen.dart';
import 'package:voxon360/src/screens/sign_in_screen.dart';

const _brand = Branding(displayName: 'VOXON 360', primaryColorHex: '#1B5E20');

class Voxon360App extends StatelessWidget {
  const Voxon360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VOXON 360',
      debugShowCheckedModeBanner: false,
      theme: BrandTheme.light(_brand),
      darkTheme: BrandTheme.dark(_brand),
      home: const _Gate(),
    );
  }
}

/// Sesión → sin negocios: crear el primero → con negocios: administrarlos.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const loading = Scaffold(body: Center(child: CircularProgressIndicator()));
    return ref
        .watch(userIdProvider)
        .when(
          loading: () => loading,
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (uid) {
            if (uid == null) return const SignInScreen();
            return ref
                .watch(myInstancesProvider)
                .when(
                  loading: () => loading,
                  error: (error, _) =>
                      Scaffold(body: Center(child: Text('$error'))),
                  data: (instances) => instances.isEmpty
                      ? const OnboardingScreen()
                      : HomeScreen(instances: instances),
                );
          },
        );
  }
}
