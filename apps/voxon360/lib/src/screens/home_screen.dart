import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon360/src/providers.dart';
import 'package:voxon360/src/screens/devices_screen.dart';
import 'package:voxon360/src/screens/staff_screen.dart';
import 'package:voxon360/src/widgets/mode_visuals.dart';

/// Administración de un negocio: inicio, cajas y empleados.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.instances});

  final List<MyInstance> instances;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _section = 0;

  static const _destinations = [
    (
      label: 'Inicio',
      icon: Icons.dashboard_outlined,
      selected: Icons.dashboard,
    ),
    (
      label: 'Cajas',
      icon: Icons.point_of_sale_outlined,
      selected: Icons.point_of_sale,
    ),
    (label: 'Empleados', icon: Icons.badge_outlined, selected: Icons.badge),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedInstanceProvider);
    final instance = widget.instances.firstWhere(
      (candidate) => candidate.id == selectedId,
      orElse: () => widget.instances.first,
    );
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final body = switch (_section) {
      0 => _Overview(
        instance: instance,
        onOpen: (section) => setState(() => _section = section),
      ),
      1 => DevicesScreen(instanceId: instance.id),
      _ => StaffScreen(instanceId: instance.id),
    };

    return Scaffold(
      appBar: AppBar(
        title: widget.instances.length == 1
            ? Text(instance.name)
            : DropdownButton<String>(
                value: instance.id,
                underline: const SizedBox.shrink(),
                onChanged: (id) =>
                    ref.read(selectedInstanceProvider.notifier).select(id),
                items: [
                  for (final option in widget.instances)
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(option.name),
                    ),
                ],
              ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            onSelected: (_) => ref.read(accountAuthServiceProvider).signOut(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _section,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) =>
                      setState(() => _section = index),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selected),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: (index) =>
                  setState(() => _section = index),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selected),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.instance, required this.onOpen});

  final MyInstance instance;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = instance.businessMode;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (mode != null) ModeBadge(mode: mode, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(instance.name, style: theme.textTheme.headlineSmall),
                      Text(mode?.name ?? instance.mode),
                      Text(
                        'Tu puesto: ${instance.role.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Para empezar', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => onOpen(2),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar empleados con PIN'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => onOpen(1),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Vincular una caja'),
            ),
          ],
        ),
      ],
    );
  }
}
