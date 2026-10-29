import 'package:flutter/material.dart';

import '../services/backend_access.dart';

class DemoAccessPage extends StatefulWidget {
  const DemoAccessPage({super.key, this.access});
  final BackendAccess? access;
  @override
  State<DemoAccessPage> createState() => _DemoAccessPageState();
}

class _DemoAccessPageState extends State<DemoAccessPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  BackendAccess get access => widget.access ?? BackendAccess.instance;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await access.connect(_code.text);
      _code.clear();
    } on DemoAccessException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI demo access')),
    body: ListenableBuilder(
      listenable: access,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.vpn_key_outlined, size: 44),
              const SizedBox(height: 20),
              Text(
                access.connected
                    ? 'Your AI demo is connected.'
                    : 'Try the live Meta AI features.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Use the private demo code supplied by the app owner. You do not need your own Meta API key or an external account. This code is not a Meta API key.',
              ),
              const SizedBox(height: 20),
              if (!access.available)
                const Text(
                  'The hosted backend is not configured in this build. You can still explore the app and use the labeled practice hearings.',
                ),
              if (access.connected) ...[
                const Text(
                  'Access is temporary and has a limited allowance. Photos and testimony are sent only after the separate upload confirmations.',
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _busy ? null : access.disconnect,
                  child: const Text('Disconnect demo'),
                ),
              ] else ...[
                TextField(
                  controller: _code,
                  enabled: access.available && !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 128,
                  decoration: const InputDecoration(
                    labelText: 'Private demo code',
                  ),
                  onSubmitted: (_) {
                    if (access.available && !_busy) _connect();
                  },
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: access.available && !_busy ? _connect : null,
                  child: Text(_busy ? 'Connecting…' : 'Connect to the demo'),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'The code and session stay in memory and are cleared when you close the app. Ask the app owner for a new code if access has expired or its allowance is exhausted.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
