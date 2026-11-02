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
        title: const Text('Invite your partner to a session'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: text,
            autofocus: true,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Session topic',
              hintText: 'What would you like to work through together?',
              alignLabelWithHint: true,
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
            child: const Text('Invite to session'),
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
          () => _error = 'Could not send the session invite. Check your connection and retry.',
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
      title: const Text('Metherapy'),
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
                Container(
                  height: 210,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFC8AB),
                        Color(0xFFFF9D96),
                        Color(0xFFFFAF9D),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 96,
                      color: Color(0xFF1597F2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'A calm space to hear each other.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.store.yourName} & ${widget.store.partnerName} · Your private Metherapy session',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Take turns, share optional photos for context, and work toward a voluntary next step with a supportive AI facilitator. Metherapy is not a licensed therapist or a substitute for professional care.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _newCase,
                  icon: const Icon(Icons.favorite_outline_rounded),
                  label: Text(
                    _busy ? 'Opening session…' : 'Invite partner to a session',
                  ),
                ),
                if (_error != null) Text(_error!),
                if (widget.store.storageError != null)
                  Text(widget.store.storageError!),
                const SizedBox(height: 32),
                Text(
                  'Previous sessions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (cases.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No sessions yet. Your partner will see your invite in chat.',
                    ),
                  ),
                for (final item in cases)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: Text(
                        item['text'] as String? ?? 'Metherapy session',
                      ),
                      subtitle: Text(
                        item['status'] == 'closed'
                            ? 'Complete · View session'
                            : 'Invite · Enter session',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(item['id'] as String),
                    ),
                  ),
                TextButton(
                  onPressed: () => widget.store.refresh(),
                  child: const Text('Refresh sessions'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
