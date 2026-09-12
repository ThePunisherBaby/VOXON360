import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Primera vez: datos del negocio y PIN del dueño.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _rnc = TextEditingController();
  final _ownerName = TextEditingController();
  final _pin = TextEditingController();
  String _businessType = 'colmado';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _rnc, _ownerName, _pin]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final client = ref.read(voxonClientProvider);
    if (client == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await client.call('business.setup', {
        'business': {
          'name': _name.text,
          'businessType': _businessType,
          'rnc': _rnc.text.trim().isEmpty ? null : _rnc.text,
        },
        'owner': {'name': _ownerName.text, 'pin': _pin.text},
      });
      ref.invalidate(businessStatusProvider);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String? required(String? value) =>
        value == null || value.trim().isEmpty ? l10n.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.setupSubtitle, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: l10n.setupBusinessName,
                    border: const OutlineInputBorder(),
                  ),
                  validator: required,
                ),
                const SizedBox(height: 8),
                Text(l10n.setupBusinessType, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'colmado',
                      label: Text(l10n.businessTypeColmado),
                    ),
                    ButtonSegment(
                      value: 'store',
                      label: Text(l10n.businessTypeStore),
                    ),
                    ButtonSegment(
                      value: 'restaurant',
                      label: Text(l10n.businessTypeRestaurant),
                    ),
                  ],
                  selected: {_businessType},
                  onSelectionChanged: (selection) =>
                      setState(() => _businessType = selection.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _rnc,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.setupRnc,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.setupOwnerSection,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ownerName,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: l10n.setupOwnerName,
                    border: const OutlineInputBorder(),
                  ),
                  validator: required,
                ),
                TextFormField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.setupOwnerPin,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.length < 4
                      ? l10n.loginPinLength
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.setupAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
