import 'package:flutter/material.dart';
import 'package:voxon_data/voxon_data.dart';

/// Botones grandes con los empleados de la caja: se toca el nombre y luego el PIN.
class StaffPicker extends StatelessWidget {
  const StaffPicker({super.key, required this.staff, required this.onSelected});

  final List<StaffMember> staff;
  final ValueChanged<StaffMember> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (staff.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Todavía no hay empleados.\nEl dueño los agrega en VOXON 360 → Empleados.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: [
        for (final member in staff)
          SizedBox(
            width: 132,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('empleado-${member.id}'),
                onTap: () => onSelected(member),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        child: Text(
                          member.initials,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        member.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(member.role.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
