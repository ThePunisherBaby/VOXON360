import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_domain/voxon_domain.dart';

import 'package:voxon360/src/providers.dart';
import 'package:voxon360/src/widgets/mode_visuals.dart';

/// Crear el primer negocio en tres pasos: tipo, datos y vista previa.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = 3;

  final _businessName = TextEditingController();
  final _accountName = TextEditingController();
  int _step = 0;
  BusinessMode? _mode;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _businessName.dispose();
    _accountName.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    0 => _mode != null,
    1 => _businessName.text.trim().isNotEmpty,
    _ => !_busy,
  };

  Future<void> _create() async {
    final mode = _mode;
    if (mode == null) return;
    final business = _businessName.text.trim();
    final account = _accountName.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminServiceProvider)
          .createAccount(
            accountName: account.isEmpty ? business : account,
            instanceName: business,
            mode: mode.id,
          );
    } on VoxonException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _create();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titles = [
      '¿Qué tipo de negocio tienes?',
      'Datos de tu negocio',
      'Así queda tu negocio',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear tu negocio'),
        leading: _step == 0
            ? null
            : BackButton(onPressed: () => setState(() => _step--)),
        actions: [
          TextButton(
            onPressed: () => ref.read(accountAuthServiceProvider).signOut(),
            child: const Text('Salir'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _steps),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Paso ${_step + 1} de $_steps',
                  style: theme.textTheme.labelLarge,
                ),
                Text(titles[_step], style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                switch (_step) {
                  0 => _ModeStep(
                    selected: _mode,
                    onSelected: (mode) => setState(() => _mode = mode),
                  ),
                  1 => _DetailsStep(
                    businessName: _businessName,
                    accountName: _accountName,
                    onChanged: () => setState(() {}),
                  ),
                  _ => _PreviewStep(
                    mode: _mode!,
                    businessName: _businessName.text.trim(),
                  ),
                },
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 20),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    key: const Key('siguiente'),
                    onPressed: _canContinue ? _next : null,
                    icon: Icon(
                      _step == _steps - 1
                          ? Icons.rocket_launch
                          : Icons.arrow_forward,
                    ),
                    label: Text(
                      _step == _steps - 1 ? 'Crear mi negocio' : 'Siguiente',
                    ),
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

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.selected, required this.onSelected});

  final BusinessMode? selected;
  final ValueChanged<BusinessMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final modes = ModeCatalog.standard.modes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 220).floor().clamp(1, 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 170,
          ),
          itemCount: modes.length,
          itemBuilder: (context, index) {
            final mode = modes[index];
            return ModeCard(
              key: Key('modo-${mode.id}'),
              mode: mode,
              selected: selected?.id == mode.id,
              onTap: () => onSelected(mode),
            );
          },
        );
      },
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.businessName,
    required this.accountName,
    required this.onChanged,
  });

  final TextEditingController businessName;
  final TextEditingController accountName;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('nombre-negocio'),
          controller: businessName,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre del negocio',
            hintText: 'Como lo conocen tus clientes',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('nombre-cuenta'),
          controller: accountName,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre de la empresa (opcional)',
            helperText:
                'Si tendrás varias sucursales, el nombre que las agrupa',
          ),
        ),
      ],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.mode, required this.businessName});

  final BusinessMode mode;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(mode.colorValue);
    final catalog = ModeCatalog.standard;
    final plans = PlanCatalog.standard;
    final trial = plans.of(plans.trialTier);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: color,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    child: Icon(modeIcon(mode.icon), size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          mode.name,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Viene listo con', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final module in mode.modules)
                      Chip(
                        avatar: const Icon(Icons.check, size: 18),
                        label: Text(catalog.moduleNames[module] ?? module),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Categorías para empezar',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(mode.categories.join(' · ')),
                const SizedBox(height: 16),
                Text(
                  mode.priceMode == PriceMode.taxIncluded
                      ? 'Precios con ITBIS incluido'
                      : 'El ITBIS se suma al precio${mode.legalTip ? ' y se cobra la propina legal del 10 %' : ''}',
                ),
                const SizedBox(height: 16),
                Text(
                  'Prueba gratis de ${plans.trialDays} días del plan ${trial.name}: '
                  '${trial.limits.devices == 0 ? 'cajas ilimitadas' : 'hasta ${trial.limits.devices} cajas'} con VOXON POS.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
