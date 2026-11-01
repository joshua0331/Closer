import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/cloud_couple_store.dart';
import '../services/backend_access.dart';
import 'shared_court.dart';
import 'demo_access_page.dart';

class CourtHome extends StatefulWidget {
  const CourtHome({super.key, required this.store});
  final CloudCoupleStore store;
  @override
  State<CourtHome> createState() => _CourtHomeState();
}

class _CourtHomeState extends State<CourtHome> {
  bool _busy = false;
  String? _error;
  Future<void> _newCase() async {
    final text = TextEditingController();
    final issue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File a case'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: text,
            autofocus: true,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'Explain the disagreement. You can request compensation in court.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text.trim());
              }
            },
            child: const Text('Send summons'),
          ),
        ],
      ),
    );
    // The dialog route finishes its transition before its controller is released.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (issue == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.store.addMessage(issue, summons: true);
      if (mounted) await _open(id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not file the case. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String id) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SharedCourt(store: widget.store, caseId: id),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Couple Court'),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const DemoAccessPage()),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('AI access'),
        ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            BackendAccess.instance.disconnect();
            await FirebaseAuth.instance.signOut();
          },
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final cases = widget.store.messages
            .where((m) => m['kind'] == 'court')
            .toList()
            .reversed
            .toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 1672 / 941,
                    child: Image.asset(
                      'assets/court/courtroom.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'A fair turn for both of you.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.store.yourName} & ${widget.store.partnerName} · Your private courtroom',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share photo evidence, question each other, and let Muse Spark propose a ruling. Muse Wonder reviews appeals. Every outcome is voluntary; this is not legal advice.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _newCase,
                  icon: const Icon(Icons.gavel),
                  label: Text(_busy ? 'Opening court…' : 'File a new case'),
                ),
                if (_error != null) Text(_error!),
                if (widget.store.storageError != null)
                  Text(widget.store.storageError!),
                const SizedBox(height: 32),
                Text(
                  'Your cases',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (cases.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No cases yet. Your partner will see a summons here when you file one.',
                    ),
                  ),
                for (final item in cases)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.gavel),
                      title: Text(item['text'] as String? ?? 'Couple Court'),
                      subtitle: Text(
                        item['status'] == 'closed'
                            ? 'Closed · View hearing'
                            : 'Open · Enter hearing',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(item['id'] as String),
                    ),
                  ),
                TextButton(
                  onPressed: () => widget.store.refresh(),
                  child: const Text('Refresh cases'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
