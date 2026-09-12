import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voxon90/core/backend/backend_exception.dart';
import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/backend/connection_providers.dart';
import 'package:voxon90/core/backend/server_discovery.dart';
import 'package:voxon90/l10n/app_localizations.dart';

/// Elegir la caja principal: la busca en el WiFi o se escribe su dirección.
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _address = TextEditingController();
  List<DiscoveredServer> _servers = const [];
  bool _searching = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final servers = await ref.read(serverFinderProvider)();
      if (mounted) setState(() => _servers = servers);
    } on Object {
      if (mounted) setState(() => _servers = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _connect(Uri uri) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await ref.read(serverProbeProvider)(uri);
      await ref.read(serverUriProvider.notifier).select(uri);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _connectManual() {
    final uri = parseServerAddress(_address.text);
    if (uri == null) {
      setState(
        () => _error = AppLocalizations.of(context).connectInvalidAddress,
      );
      return;
    }
    _connect(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.connectSubtitle, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              if (_searching) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l10n.connectSearching),
              ] else if (_servers.isEmpty)
                Text(l10n.connectNoneFound)
              else
                for (final server in _servers)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.point_of_sale),
                      title: Text(server.name ?? l10n.connectUnnamedBusiness),
                      subtitle: Text(
                        '${server.address.address}:${server.httpPort}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_connecting,
                      onTap: () => _connect(server.baseUri),
                    ),
                  ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.connectSearchAgain),
                ),
              ),
              const Divider(height: 32),
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.connectManualLabel,
                  hintText: '192.168.1.10',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _connectManual(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _connecting ? null : _connectManual,
                child: Text(l10n.connectManualAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
