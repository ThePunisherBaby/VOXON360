import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90_owner/data/owner_repository.dart';
import 'package:voxon90_owner/providers.dart';

/// Negocios del dueño. Casi siempre hay uno solo.
class BusinessesScreen extends ConsumerWidget {
  const BusinessesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewBusinessDialog(),
    );
    if (name == null || name.isEmpty) return;
    try {
      final business = await ref
          .read(ownerRepositoryProvider)
          .createBusiness(name);
      ref.read(selectedBusinessProvider.notifier).select(business.id);
    } on OwnerException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(businessesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tus negocios'),
        actions: [
          IconButton(
            tooltip: 'Salir',
            onPressed: () => ref.read(ownerRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo negocio'),
      ),
      body: businesses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Todavía no tienes un negocio.\nCrea uno y vincula tu caja principal.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                children: [
                  for (final business in items)
                    ListTile(
                      leading: const Icon(Icons.storefront),
                      title: Text(business.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ref
                          .read(selectedBusinessProvider.notifier)
                          .select(business.id),
                    ),
                ],
              ),
      ),
    );
  }
}

class _NewBusinessDialog extends StatefulWidget {
  const _NewBusinessDialog();

  @override
  State<_NewBusinessDialog> createState() => _NewBusinessDialogState();
}

class _NewBusinessDialogState extends State<_NewBusinessDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: const Text('Nuevo negocio'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Nombre del negocio'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}
