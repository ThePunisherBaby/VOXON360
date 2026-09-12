import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90_owner/providers.dart';
import 'package:voxon90_owner/screens/businesses_screen.dart';
import 'package:voxon90_owner/screens/dashboard_screen.dart';
import 'package:voxon90_owner/screens/sign_in_screen.dart';

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B5E20);
    return MaterialApp(
      title: 'VOXON90 Dueño',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: const _Gate(),
    );
  }
}

/// Sesión → negocio elegido → resumen.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(userIdProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (userId) {
            if (userId == null) return const SignInScreen();
            final businessId = ref.watch(selectedBusinessProvider);
            return businessId == null
                ? const BusinessesScreen()
                : DashboardScreen(businessId: businessId);
          },
        );
  }
}
