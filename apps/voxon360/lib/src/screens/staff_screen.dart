import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';

import 'package:voxon360/src/providers.dart';

/// Empleados del negocio y su PIN para entrar en las cajas.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key, required this.instanceId});

  final String instanceId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    StaffMember? member,
  ]) async {
    final result = await showDialog<_StaffForm>(
      context: context,
      builder: (context) => _StaffDialog(member: member),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(adminServiceProvider)
          .saveStaff(
            instanceId: instanceId,
            staffId: member?.id,
            name: result.name,
            role: result.role,
            pin: result.pin,
            active: result.active,
          );
    } on VoxonException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final staff = ref.watch(staffListProvider(instanceId));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Empleados', style: theme.textTheme.headlineSmall),
        const Text(
          'Cada empleado entra en las cajas tocando su nombre y escribiendo su PIN.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Agregar empleado'),
          ),
        ),
        const SizedBox(height: 20),
        staff.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
          data: (members) => members.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no hay empleados.'),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final member in members)
                        ListTile(
                          leading: CircleAvatar(child: Text(member.initials)),
                          title: Text(member.name),
                          subtitle: Text(
                            member.active
                                ? member.role.label
                                : '${member.role.label} · desactivado',
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _edit(context, ref, member),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _StaffForm {
  const _StaffForm({
    required this.name,
    required this.role,
    required this.pin,
    required this.active,
  });

  final String name;
  final StaffRole role;

  /// null = no cambiar el PIN.
  final String? pin;
  final bool active;
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({this.member});

  final StaffMember? member;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  final _pin = TextEditingController();
  late StaffRole _role = widget.member?.role ?? StaffRole.cashier;
  late bool _active = widget.member?.active ?? true;
  String? _error;

  bool get _isNew => widget.member == null;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre');
      return;
    }
    if ((_isNew || pin.isNotEmpty) && !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'El PIN tiene de 4 a 6 números');
      return;
    }
    Navigator.pop(
      context,
      _StaffForm(
        name: name,
        role: _role,
        pin: pin.isEmpty ? null : pin,
        active: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo empleado' : 'Editar empleado'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('empleado-nombre'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<StaffRole>(
              key: const Key('empleado-puesto'),
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Puesto'),
              items: [
                for (final role in StaffRole.assignable)
                  DropdownMenuItem(value: role, child: Text(role.label)),
              ],
              onChanged: (role) => setState(() => _role = role ?? _role),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('empleado-pin'),
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: _isNew
                    ? 'PIN (4 a 6 números)'
                    : 'PIN nuevo (opcional)',
                errorText: _error,
              ),
            ),
            if (!_isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
