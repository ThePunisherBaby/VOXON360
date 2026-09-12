import 'package:flutter/material.dart';
import 'package:voxon_domain/voxon_domain.dart';

/// Ícono de Material para el nombre que trae shared/modes.json.
IconData modeIcon(String name) => switch (name) {
  'local_grocery_store' => Icons.local_grocery_store,
  'storefront' => Icons.storefront,
  'restaurant' => Icons.restaurant,
  'shopping_bag' => Icons.shopping_bag,
  'local_bar' => Icons.local_bar,
  'local_cafe' => Icons.local_cafe,
  'fastfood' => Icons.fastfood,
  'local_pharmacy' => Icons.local_pharmacy,
  'hardware' => Icons.hardware,
  'checkroom' => Icons.checkroom,
  'ice_skating' => Icons.ice_skating,
  'smartphone' => Icons.smartphone,
  'content_cut' => Icons.content_cut,
  'liquor' => Icons.liquor,
  'set_meal' => Icons.set_meal,
  'eco' => Icons.eco,
  'menu_book' => Icons.menu_book,
  'car_repair' => Icons.car_repair,
  'icecream' => Icons.icecream,
  'local_laundry_service' => Icons.local_laundry_service,
  _ => Icons.store,
};

/// Círculo con el color y el ícono del modo.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.mode, this.size = 48});

  final BusinessMode mode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(mode.colorValue);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.15),
      foregroundColor: color,
      child: Icon(modeIcon(mode.icon), size: size * 0.55),
    );
  }
}

/// Tarjeta de un modo para elegirlo al crear el negocio.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final BusinessMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(mode.colorValue);
    final available = mode.isAvailable;
    return Opacity(
      opacity: available ? 1 : 0.45,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? color : theme.colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: InkWell(
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ModeBadge(mode: mode, size: 44),
                    const Spacer(),
                    if (!available)
                      const Chip(
                        label: Text('Pronto'),
                        visualDensity: VisualDensity.compact,
                      )
                    else if (selected)
                      Icon(Icons.check_circle, color: color),
                  ],
                ),
                const SizedBox(height: 10),
                Text(mode.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                // Ocupa lo que quede de la tarjeta, aunque el texto venga grande.
                Expanded(
                  child: Text(
                    mode.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
