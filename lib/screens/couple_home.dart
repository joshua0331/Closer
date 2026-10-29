import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/couple_store.dart';
import 'court_experience.dart';
import 'couple_map.dart';
import 'demo_access_page.dart';

class CoupleHome extends StatefulWidget {
  const CoupleHome({super.key, required this.store});
  final CoupleStore store;
  @override
  State<CoupleHome> createState() => _CoupleHomeState();
}

class _CoupleHomeState extends State<CoupleHome> {
  int _tab = 0;
  bool _picking = false;
  Map<String, dynamic>? _replyTo;
  final _message = TextEditingController();
  final _scroll = ScrollController();
  CoupleStore get store => widget.store;

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _demoAccess() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DemoAccessPage()));
    if (mounted) setState(() {});
  }

  Future<void> _profile() async {
    final names = await showDialog<List<String>>(
      context: context,
      builder: (_) => _ProfileDialog(
        yourName: store.yourName,
        partnerName: store.partnerName,
      ),
    );
    if (names == null || !mounted) return;
    store.yourName = names[0];
    store.partnerName = names[1];
    await store.save();
  }

  Future<void> _summon() async {
    if (!store.hasProfile) {
      await _profile();
      if (!store.hasProfile || !mounted) return;
    }
    final issue = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(
        title: 'Summon your partner',
        label: 'What would you like to talk about?',
        description: 'This preview adds a court card to your local chat. No notification is sent.',
        action: 'Add court summons',
      ),
    );
    if (issue == null || !mounted) return;
    await store.addMessage(issue, summons: true);
    if (mounted) setState(() => _tab = 3);
  }

  Future<void> _openCourt(Map<String, dynamic> message) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourtExperience(
          preferences: store.preferences,
          initialNames: [store.yourName, store.partnerName],
          initialTopic: message['text'] as String,
          caseId: message['id'] as String,
          onCaseClosed: (record) =>
              store.finishCourt(message['id'] as String, record),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _attachChatPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final caption = await showDialog<String>(
        context: context,
        builder: (_) => const _TextDialog(
          title: 'A photo for your conversation',
          label: 'Caption (optional)',
          description: 'This photo stays in your local Closer chat until online sharing is connected.',
          action: 'Add to chat',
          allowEmpty: true,
        ),
      );
      if (caption == null || !mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      final folder = await Directory('${directory.path}/us_chat')
          .create(recursive: true);
      final path =
          '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await image.saveTo(path);
      if (!mounted) return;
      await store.addMessage(caption, photoPath: path, replyTo: _replyTo);
      if (mounted) setState(() => _replyTo = null);
      _scrollChatToEnd();
    } catch (_) {
      _notice(
        'Could not add that photo. Please check photo access and try again.',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _timeLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showChatPhoto(String path) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                errorBuilder: (_, error, stack) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Photo unavailable on this device.'),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  Widget _chatEntry(Map<String, dynamic> entry) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.only(left: 24, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4D4),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (entry['replyTo'] is Map)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: ivory,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Replying to: ${(entry['replyTo'] as Map)['text'] == '' ? 'Photo' : (entry['replyTo'] as Map)['text']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (entry['kind'] == 'photo')
            GestureDetector(
              onTap: () => _showChatPhoto(entry['photoPath'] as String),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(entry['photoPath'] as String),
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    height: 100,
                    child: Center(child: Text('Photo unavailable')),
                  ),
                ),
              ),
            ),
          if ((entry['text'] as String).isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(entry['text'] as String),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_timeLabel(entry['createdAt'] as String?)} · Local only',
                style: const TextStyle(fontSize: 10, color: Color(0xFF775B50)),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Message options',
                iconSize: 18,
                padding: EdgeInsets.zero,
                onSelected: (value) async {
                  if (value == 'reply') {
                    setState(() => _replyTo = entry);
                  }
                  if (value == 'heart') {
                    await store.toggleHeart(entry['id'] as String);
                  }
                  if (value == 'copy') {
                    await Clipboard.setData(
                      ClipboardData(text: entry['text'] as String),
                    );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'reply', child: Text('Reply')),
                  PopupMenuItem(
                    value: 'heart',
                    child: Text(
                      entry['hearted'] == true ? 'Remove heart' : 'Add a heart',
                    ),
                  ),
                  if ((entry['text'] as String).isNotEmpty)
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy text'),
                    ),
                ],
              ),
            ],
          ),
          if (entry['hearted'] == true)
            const Text(
              '♥',
              style: TextStyle(color: Color(0xFFB85842), fontSize: 20),
            ),
        ],
      ),
    ),
  );

  Future<void> _addMemory() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final caption = await showDialog<String>(
        context: context,
        builder: (_) => const _TextDialog(
          title: 'A moment worth keeping',
          label: 'Write a caption',
          description: 'Your photo will be saved on this device only.',
          action: 'Keep memory',
        ),
      );
      if (caption == null || !mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      final folder = await Directory('${directory.path}/couple_memories')
          .create(recursive: true);
      final path =
          '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await image.saveTo(path);
      if (!mounted) return;
      store.memories.insert(0, {
        'path': path,
        'caption': caption,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await store.save();
    } catch (_) {
      _notice('Could not add that photo. Check photo access and try again.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _date() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: store.relationshipStart ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'When did your story begin?',
    );
    if (selected == null || !mounted) return;
    store.relationshipStart = selected;
    await store.save();
  }

  void _notifications() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: ivory,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded, size: 38, color: peach),
              SizedBox(height: 16),
              Text(
                'Your little updates',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text(
                'Partner notifications will appear here when your accounts are connected. This preview does not send notifications.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Scaffold(
      extendBody: _tab == 0,
      appBar: _tab == 0
          ? null
          : AppBar(title: Text('Closer · ${CoupleDock.labels[_tab]}')),
      bottomNavigationBar: CoupleDock(
        selected: _tab,
        onSelected: (index) => setState(() => _tab = index),
      ),
      body: _tab == 0
          ? CoupleMap(
              yourName: store.yourName,
              partnerName: store.partnerName,
              startedOn: store.relationshipStart,
              onProfile: _profile,
              onDate: _date,
              onNotifications: _notifications,
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        color: const Color(0xFFFFEADB),
                        child: const Text(
                          'LOCAL PREVIEW · No account or partner connection yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: slate),
                        ),
                      ),
                      if (store.storageError != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            store.storageError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Expanded(
                        child: switch (_tab) {
                          1 => _court(),
                          2 => _memories(),
                          3 => _chat(),
                          _ => _home(),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(subtitle),
      ],
    ),
  );

  Widget _card(
    IconData icon,
    String title,
    String description, {
    Widget? action,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(description),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );

  Widget _home() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _heading(
        store.hasProfile
            ? '${store.yourName} & ${store.partnerName}'
            : 'A little closer, every day.',
        'Closer — your conversations, your memories, your space.',
      ),
      OutlinedButton.icon(
        onPressed: _date,
        icon: const Icon(Icons.calendar_month_outlined),
        label: const Text('Our anniversary'),
      ),
      const SizedBox(height: 16),
      _card(
        Icons.link,
        store.hasProfile
            ? 'Your preview profile'
            : 'One connection. A shared space.',
        'The online version will let you create accounts and pair once by invitation. Neither partner will need to create rooms.',
        action: FilledButton(
          onPressed: _profile,
          child: Text(
            store.hasProfile ? 'Edit preview names' : 'Set preview names',
          ),
        ),
      ),
      _card(
        Icons.auto_awesome_outlined,
        'Meta AI demo access',
        'Connect with a private demo code to use the hosted judge and Muse Image. Your own Meta account is not required.',
        action: OutlinedButton(
          onPressed: _demoAccess,
          child: const Text('AI demo access'),
        ),
      ),
      _card(
        Icons.near_me_outlined,
        'Distance, when you both choose.',
        'Distance unavailable. When connected, both partners can choose to share their location and pause sharing at any time.',
      ),
      Row(
        children: [
          Expanded(child: _stat('${store.messages.length}', 'Chat entries')),
          const SizedBox(width: 12),
          Expanded(child: _stat('${store.memories.length}', 'Memories')),
        ],
      ),
      const SizedBox(height: 16),
      _card(
        Icons.balance,
        'Make room for understanding.',
        'Bring a disagreement to Couple Court and take turns being heard.',
        action: OutlinedButton(
          onPressed: _summon,
          child: const Text('Summon partner'),
        ),
      ),
    ],
  );

  Widget _stat(String value, String label) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          Text(label),
        ],
      ),
    ),
  );

  Widget _chat() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                store.hasProfile
                    ? 'You & ${store.partnerName}'
                    : 'Your conversation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: _summon,
              icon: const Icon(Icons.gavel),
              tooltip: 'Summon partner',
            ),
          ],
        ),
      ),
      Expanded(
        child: store.messages.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your story starts here.\nTry a message or add a court summons.\nEntries stay on this device.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: store.messages.length,
                itemBuilder: (context, index) {
                  final entry = store.messages[index];
                  if (entry['kind'] == 'court') return _summonsCard(entry);
                  return _chatEntry(entry);
                },
              ),
      ),
      if (_replyTo != null)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEADB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Replying to: ${(_replyTo!['text'] as String).isEmpty ? 'Photo' : _replyTo!['text']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _replyTo = null),
                tooltip: 'Cancel reply',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _picking ? null : _attachChatPhoto,
              tooltip: 'Attach chat photo',
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _message,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: 'Write a message…',
                  counterText: '',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Save local message',
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    final text = _message.text;
    _message.clear();
    await store.addMessage(text, replyTo: _replyTo);
    if (mounted) setState(() => _replyTo = null);
    _scrollChatToEnd();
  }

  Widget _summonsCard(Map<String, dynamic> entry) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.balance),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry['status'] == 'closed'
                      ? entry['courtStatus'] == 'unresolved'
                            ? 'Court · unresolved'
                            : 'Court · case closed'
                      : 'A little time in court?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(entry['text'] as String),
          const SizedBox(height: 12),
          if (entry['status'] == 'closed')
            Text('Our next step: ${entry['agreement']}')
          else
            FilledButton.tonal(
              onPressed: () => _openCourt(entry),
              child: const Text('Enter Couple Court'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Local preview · partner has not been notified',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _memories() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _heading(
        'The little things, kept.',
        'A place for photos and moments you love.',
      ),
      FilledButton.icon(
        onPressed: _picking ? null : _addMemory,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_picking ? 'Adding photo…' : 'Add a memory'),
      ),
      const SizedBox(height: 20),
      if (store.memories.isEmpty)
        _card(
          Icons.photo_camera_outlined,
          'Your first memory is waiting.',
          'Choose a photo and add a caption. Preview photos are stored on this device.',
        ),
      for (final memory in store.memories)
        Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.file(
                File(memory['path'] as String),
                height: 280,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => const SizedBox(
                  height: 160,
                  child: Center(
                    child: Text('Photo unavailable on this device'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(memory['caption'] as String),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _court() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _heading('Couple Court', 'A softer place to settle your differences.'),
      _card(
        Icons.gavel,
        'Speak. Listen. Find a next step.',
        'A pixel-art courtroom with evidence, timed questions, rebuttals, a Meta AI judge, compensation requests and appeals.',
        action: FilledButton(
          onPressed: _summon,
          child: const Text('Summon partner'),
        ),
      ),
      const Text(
        'In this preview, both turns happen on this phone. Online hearings will wait for both partners to accept.',
      ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/court/courtroom.png',
          filterQuality: FilterQuality.none,
        ),
      ),
      const SizedBox(height: 24),
      Text('Your cases', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (!store.messages.any((m) => m['kind'] == 'court'))
        const Text('No cases yet. Start with something small.'),
      for (final entry
          in store.messages
              .where((m) => m['kind'] == 'court')
              .toList()
              .reversed)
        _summonsCard(entry),
      for (final record in store.courtHistory.where(
        (record) => !store.messages.any(
          (message) =>
              message['recordId'] != null &&
              message['recordId'] == record['id'],
        ),
      ))
        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(record['topic'] as String? ?? 'Previous case'),
            subtitle: Text(
              '${record['agreement']}\n${record['practice'] == true ? 'Practice' : 'Meta judge'} · saved on this device',
            ),
            isThreeLine: true,
          ),
        ),
    ],
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.yourName, required this.partnerName});
  final String yourName;
  final String partnerName;
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _you = TextEditingController(text: widget.yourName);
  late final _partner = TextEditingController(text: widget.partnerName);
  @override
  void dispose() {
    _you.dispose();
    _partner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your preview profile'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'These names are saved locally. This does not create accounts or pair two phones.',
            ),
            const SizedBox(height: 20),
            for (final field in [
              (_you, 'Your name'),
              (_partner, 'Partner’s name'),
            ]) ...[
              TextFormField(
                controller: field.$1,
                maxLength: 50,
                decoration: InputDecoration(labelText: field.$2),
                validator: (text) => text == null || text.trim().isEmpty
                    ? 'Please enter a name.'
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
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
          if (_form.currentState!.validate()) {
            Navigator.pop(context, [_you.text.trim(), _partner.text.trim()]);
          }
        },
        child: const Text('Save names'),
      ),
    ],
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.description,
    required this.action,
    this.allowEmpty = false,
  });
  final String title, label, description, action;
  final bool allowEmpty;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.description),
            const SizedBox(height: 20),
            TextFormField(
              controller: _text,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(labelText: widget.label),
              validator: (text) =>
                  !widget.allowEmpty && (text == null || text.trim().isEmpty)
                  ? 'Please write a few words.'
                  : null,
            ),
          ],
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
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _text.text.trim());
          }
        },
        child: Text(widget.action),
      ),
    ],
  );
}
