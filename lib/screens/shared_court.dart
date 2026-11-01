import 'dart:async';

import 'package:flutter/services.dart';

import 'room_chat.dart';

import '../services/photo_media.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/cloud_couple_store.dart';
import '../services/backend_access.dart';
import '../services/judge_service.dart';
import 'animated_courtroom.dart';
import 'demo_access_page.dart';
import 'evidence_highlights.dart';

const _turns = <int, int>{
  0: 0,
  1: 0,
  2: 1,
  3: 0,
  4: 1,
  5: 1,
  6: 0,
  7: 0,
  8: 1,
  10: 0,
  11: 1,
  14: 1,
  15: 0,
};
const _titles = [
  'Requested compensation',
  'Claimant’s opening',
  'Respondent’s opening',
  'Claimant asks a question',
  'Respondent answers',
  'Respondent asks a question',
  'Claimant answers',
  'Claimant’s rebuttal',
  'Respondent’s rebuttal',
  'Questions from Muse Spark',
  'Claimant answers the judge',
  'Respondent answers the judge',
  'Muse Spark reviews the case',
  'Your first ruling',
  'Respondent’s appeal grounds',
  'Claimant responds to the appeal',
  'Muse Wonder reviews the appeal',
  'Your appeal ruling',
  'Case closed',
];

class SharedCourt extends StatefulWidget {
  const SharedCourt({
    super.key,
    required this.store,
    required this.caseId,
    this.roomInvite,
    this.onLobby,
  });
  final CloudCoupleStore store;
  final String caseId;
  final String? roomInvite;
  final VoidCallback? onLobby;
  @override
  State<SharedCourt> createState() => _SharedCourtState();
}

class _SharedCourtState extends State<SharedCourt> with WidgetsBindingObserver {
  Map<String, dynamic>? _case;
  double _clockOffset = 0;
  final _text = TextEditingController(), _caption = TextEditingController();
  Timer? _poll, _clock;
  bool _busy = false, _loading = false;
  String? _error;
  final Map<String, String> _photos = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _clock?.cancel();
    _text.dispose();
    _caption.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poll?.cancel();
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (_loading || _busy) return;
    _loading = true;
    try {
      final data = await widget.store.hearing(widget.caseId);
      await _apply(data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _apply(Map<String, dynamic> data) async {
    final phaseChanged = _case?['phase'] != data['phase'];
    for (final raw in data['evidence'] as List) {
      final e = raw as Map;
      final id = e['photoId'] as String;
      if (!_photos.containsKey(id)) {
        _photos[id] = await widget.store.photoPath(id);
      }
    }
    for (final id in (data['portraits'] as List? ?? []).whereType<String>()) {
      _photos[id] ??= await widget.store.photoPath(id);
    }
    if (data['scenePhotoId'] != null) {
      final id = data['scenePhotoId'] as String;
      _photos[id] ??= await widget.store.photoPath(id);
    }
    if (!mounted) return;
    setState(() {
      _case = data;
      if (data['serverNow'] is num) {
        _clockOffset =
            (data['serverNow'] as num).toDouble() -
            DateTime.now().millisecondsSinceEpoch / 1000;
      }
      _error = null;
      if (phaseChanged) _text.clear();
    });
  }

  Future<void> _act(String operation, {Map<String, dynamic>? extra}) async {
    if (_busy || _case == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.store.hearing(
        widget.caseId,
        body: {'operation': operation, 'version': _case!['version'], ...?extra},
      );
      await _apply(data);
      await widget.store.refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _portrait() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use your portrait for courtroom art?'),
        content: const Text(
          'Your photo is shared with your paired partner and may be sent with their separately consented portrait to Meta Muse Image to redraw you both as pixel-art characters. Portraits are not evidence. Use only a photo you have permission to share.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose my portrait'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );
    if (photo == null || !mounted) return;
    if (await photo.length() > 1000000) {
      if (mounted) {
        setState(() => _error = 'Choose a portrait smaller than 1 MB.');
      }
      return;
    }
    setState(() => _busy = true);
    String? id;
    try {
      id = await widget.store.upload(photo.path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Portrait upload failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (id != null) {
      await _act('portrait', extra: {'photoId': id, 'consent': true});
    }
  }

  Future<void> _art() async {
    if (!BackendAccess.instance.connected && widget.store.roomSession != null) {
      try {
        await BackendAccess.instance.connectRoom(widget.store.roomSession!);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Room AI access is unavailable or its allowance has expired.',
          );
        }
        return;
      }
    }
    if (!mounted) return;
    if (!BackendAccess.instance.connected) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const DemoAccessPage()),
      );
      if (mounted) setState(() {});
      return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send both portraits to Meta Muse Image?'),
        content: const Text(
          'This sends both selfies and the courtroom reference through the backend to Meta to generate your courtroom art. Confirm both people agree and have permission to share these photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate artwork'),
          ),
        ],
      ),
    );
    if (agreed == true) await _act('art');
  }

  Future<void> _review() async {
    if (!BackendAccess.instance.connected && widget.store.roomSession != null) {
      try {
        await BackendAccess.instance.connectRoom(widget.store.roomSession!);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'Room AI access is unavailable or its allowance has expired.',
          );
        }
        return;
      }
    }
    if (!mounted) return;
    if (!BackendAccess.instance.connected) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const DemoAccessPage()),
      );
      if (mounted) setState(() {});
      return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send the shared case to Meta?'),
        content: const Text(
          'This sends both names, testimony, requested remedy and original evidence photos to Meta through Couple Court’s backend. Confirm you have permission. The proposed outcome is voluntary and photos cannot establish authenticity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ask the judge'),
          ),
        ],
      ),
    );
    if (agreed == true) await _act('review');
  }

  Future<void> _attach() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 65,
    );
    if (image == null || !mounted) return;
    if (await image.length() > 1000000) {
      if (mounted) {
        setState(() => _error = 'Choose an evidence photo smaller than 1 MB.');
      }
      return;
    }
    if (!mounted) return;
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Describe this exhibit'),
        content: TextField(
          controller: _caption,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Caption · a claim, not verified fact',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _caption.text.trim()),
            child: const Text('Share exhibit'),
          ),
        ],
      ),
    );
    if (caption == null || caption.isEmpty || !mounted) return;
    setState(() => _busy = true);
    String? id;
    try {
      id = await widget.store.upload(image.path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not upload this exhibit.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (id != null) {
      await _act('evidence', extra: {'photoId': id, 'caption': caption});
    }
    _caption.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Couple Court')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Opening your shared hearing…'),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final phase = c['phase'] as int,
        role = (c['people'] as List).indexOf(widget.store.uid);
    final both = (c['joined'] as List).length == 2,
        joined = (c['joined'] as List).contains(widget.store.uid);
    final deadline = c['deadline'] as num?;
    final seconds = deadline == null
        ? 0
        : (deadline -
                  (DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset))
              .ceil()
              .clamp(0, 120);
    final myTurn = _turns[phase] == role;
    final ruling = c['ruling'] as Map?;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onLobby == null
            ? null
            : IconButton(
                onPressed: widget.onLobby,
                tooltip: 'Room lobby',
                icon: const Icon(Icons.arrow_back),
              ),
        title: const Text('Couple Court'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh hearing',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.roomInvite != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Invite your partner',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Private one-use link · expires 24 hours after creation. Each of you keeps your own browser session.',
                          ),
                          SelectableText(widget.roomInvite!),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: widget.roomInvite!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invite link copied'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy invitation'),
                          ),
                        ],
                      ),
                    ),
                  ),
                AnimatedCourtroom(store: widget.store, hearing: c),
                if (_photos[c['scenePhotoId']] != null)
                  ExpansionTile(
                    title: const Text('Our Muse Image courtroom artwork'),
                    children: [
                      photoImage(
                        _photos[c['scenePhotoId']]!,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                if (widget.store.roomSession != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Expanded(
                          child: Column(
                            children: [
                              if (_photos[(c['portraits'] as List? ??
                                      [null, null])[i]] !=
                                  null)
                                ClipOval(
                                  child: photoImage(
                                    _photos[(c['portraits'] as List)[i]]!,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                const CircleAvatar(
                                  radius: 28,
                                  child: Icon(Icons.person_outline),
                                ),
                              Text(
                                (c['names'] as List)[i] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  RoomChat(store: widget.store, initiallyExpanded: false),
                  if (phase == 0)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _attach,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text(
                        'Add evidence before the hearing · up to 2 each',
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                Text(
                  c['topic'] as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  _titles[phase],
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'You are the ${role == 0 ? 'claimant' : 'respondent'}. Both browsers use the same hearing.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (!both && phase == 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    (c['portraits'] as List? ?? [null, null])[role] == null
                        ? 'Optional: add your own portrait before entering.'
                        : 'Your portrait is ready for Muse Image.',
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _portrait,
                    icon: const Icon(Icons.face_outlined),
                    label: const Text('Choose my portrait · consent required'),
                  ),
                  if ((c['portraits'] as List? ?? []).length == 2 &&
                      (c['portraits'] as List).every((p) => p != null))
                    FilledButton.tonal(
                      onPressed: _busy ? null : _art,
                      child: const Text('Generate our courtroom · Muse Image'),
                    ),
                  if (c['sceneModel'] != null)
                    Text('Artwork: ${c['sceneModel']}'),
                ],
                if (!both) ...[
                  const SizedBox(height: 14),
                  Text(
                    joined
                        ? 'Waiting for your partner to enter this summons.'
                        : 'Both partners must enter before the hearing starts.',
                  ),
                  FilledButton(
                    onPressed: _busy || joined ? null : () => _act('join'),
                    child: Text(
                      joined ? 'You entered court' : 'Enter shared hearing',
                    ),
                  ),
                ] else if (_turns.containsKey(phase)) ...[
                  const SizedBox(height: 14),
                  Text('$seconds seconds remaining · server deadline'),
                  if (phase == 0)
                    const Text(
                      'What small practical action would you like as compensation? Both people can decline the final proposal.',
                    ),
                  if (phase == 4)
                    Text('Question: ${(c['crossQuestions'] as List)[0]}'),
                  if (phase == 6)
                    Text('Question: ${(c['crossQuestions'] as List)[1]}'),
                  if (phase == 10 || phase == 11)
                    Text(
                      'Judge asks: ${(c['judgeQuestions'] as List)[phase - 10]}',
                    ),
                  if (phase == 15) Text('Appeal grounds: ${c['appealReason']}'),
                  if (myTurn && seconds > 0) ...[
                    TextField(
                      controller: _text,
                      maxLines: 5,
                      maxLength: phase == 0 ? 1000 : 2000,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Your turn'),
                    ),
                    if (phase >= 1 && phase <= 8)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _attach,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photo evidence · up to 2 each'),
                      ),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              'turn',
                              extra: {'text': _text.text.trim()},
                            ),
                      child: const Text('Submit my turn'),
                    ),
                  ] else if (seconds == 0)
                    FilledButton(
                      onPressed: _busy ? null : () => _act('turn'),
                      child: const Text('Continue after expired turn'),
                    )
                  else
                    Text(
                      'Waiting for ${(c['names'] as List)[_turns[phase]!]} to take their turn.',
                    ),
                ] else if ({9, 12, 16}.contains(phase)) ...[
                  const SizedBox(height: 14),
                  Text(
                    phase == 16
                        ? 'Muse Wonder reviews the prior ruling, appeal grounds and response.'
                        : 'Muse Spark examines the full record and original evidence.',
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _review,
                    child: Text(
                      BackendAccess.instance.connected
                          ? 'Request ${phase == 16 ? 'Wonder appeal review' : 'Spark review'}'
                          : widget.store.roomSession != null
                          ? 'Connect room AI access'
                          : 'Connect private AI demo access',
                    ),
                  ),
                ],
                if (ruling != null) ...[
                  const Divider(height: 30),
                  Text('Model: ${c['model']}'),
                  Text('Requested: ${ruling['requestedRemedy']}'),
                  Text(
                    'Proposed: ${ruling['proposedRemedy']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(ruling['reasoning'] as String),
                  Text('Limits: ${ruling['uncertainties']}'),
                ],
                if (phase == 13 || phase == 17) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        _busy ||
                            (c['approved'] as List).contains(widget.store.uid)
                        ? null
                        : () => _act('accept'),
                    child: Text(
                      (c['approved'] as List).contains(widget.store.uid)
                          ? 'Accepted · waiting for partner'
                          : 'Accept this proposal',
                    ),
                  ),
                  if (phase == 13 && role == 1)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _act('appeal'),
                      child: const Text('Appeal once'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : () => _act('decline'),
                    child: const Text('Decline · close unresolved'),
                  ),
                ],
                if (phase == 18)
                  Text(
                    c['closedStatus'] == 'accepted'
                        ? 'Both partners accepted this proposal.'
                        : 'Closed without mutual acceptance.',
                  ),
                if (widget.store.roomSession != null)
                  SelectableText(
                    'Room ID: ${widget.store.couple?['id'] ?? ''}',
                  ),
                const Divider(height: 32),
                const Text(
                  'Evidence · original photos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final raw in c['evidence'] as List)
                  Builder(
                    builder: (context) {
                      final e = raw as Map;
                      final path = _photos[e['photoId']];
                      return ListTile(
                        leading: path == null
                            ? const Icon(Icons.image)
                            : photoImage(
                                path,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                        title: Text('${e['id']} · ${e['caption']}'),
                        subtitle: const Text(
                          'Tap to view original or request SAM object highlights',
                        ),
                        onTap: path == null
                            ? null
                            : () async {
                                final judge = JudgeService();
                                try {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => EvidenceHighlights(
                                        path: path,
                                        caption: e['caption'] as String,
                                        judge: judge,
                                      ),
                                    ),
                                  );
                                } finally {
                                  judge.close();
                                }
                              },
                      );
                    },
                  ),
                for (final review in c['evidenceReview'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${review['id']}: ${review['observation']}\nLimit: ${review['limitation']}',
                    ),
                  ),
                const Divider(height: 32),
                const Text(
                  'Shared record',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final field in [
                  'requestedRemedy',
                  'statements',
                  'crossQuestions',
                  'crossAnswers',
                  'rebuttals',
                  'judgeQuestions',
                  'judgeAnswers',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      '$field: ${c[field] is List ? (c[field] as List).join(' · ') : c[field]}',
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
