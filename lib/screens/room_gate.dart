import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legal_page.dart';

import '../models/cloud_couple_store.dart';
import '../services/backend_access.dart';
import '../services/photo_media.dart';
import 'couple_court_brand.dart';
import 'shared_court.dart';
import 'courtroom_preview.dart';

class RoomGate extends StatefulWidget {
  const RoomGate({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  State<RoomGate> createState() => _RoomGateState();
}

class _RoomGateState extends State<RoomGate> with WidgetsBindingObserver {
  static const _sessionKey = 'court_guest_session_v1';
  final _name = TextEditingController(),
      _topic = TextEditingController(),
      _invite = TextEditingController();
  CloudCoupleStore? _store;
  Map<String, dynamic>? _session;
  String? _photo, _error;
  bool _join = false, _busy = false, _consent = false, _open = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final fragment = Uri.tryParse('https://local/?${Uri.base.fragment}');
    final code = fragment?.queryParameters['invite'];
    if (code != null) {
      _join = true;
      _invite.text = code;
    }
    final saved = widget.preferences.getString(_sessionKey);
    if (saved != null) {
      try {
        final session = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        if ((session['expires'] as num) >
                DateTime.now().millisecondsSinceEpoch / 1000 &&
            (code == null || code == session['invite'])) {
          _restore(session);
        }
      } catch (_) {
        /* An invalid local session never grants access. */
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _store?.resume();
    } else {
      _store?.pause();
    }
  }

  Future<void> _restore(Map<String, dynamic> session) async {
    setState(() => _busy = true);
    try {
      await _activate(session);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not restore that browser session. Create or join a room below.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(Map<String, dynamic> session) async {
    final store = CloudCoupleStore(
      widget.preferences,
      null,
      roomSession: session['session'] as String,
      roomUid: session['uid'] as String,
    );
    BackendAccess.instance.disconnect();
    try {
      await BackendAccess.instance.connectRoom(session['session'] as String);
    } catch (_) {
      /* Room and chat remain usable when the AI allowance is unavailable. */
    }
    await store.start();
    if (!mounted) {
      store.dispose();
      return;
    }
    _store?.dispose();
    setState(() {
      _store = store;
      _session = session;
      _open = true;
    });
  }

  String _code(String value) {
    final input = value.trim();
    final uri = Uri.tryParse(input);
    if (uri != null && uri.hasScheme) {
      return Uri.tryParse('https://local/?${uri.fragment}')
              ?.queryParameters['invite'] ??
          '';
    }
    return input;
  }

  Future<void> _pick() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 1000000) {
        throw Exception('Choose a JPEG or PNG selfie smaller than 1 MB.');
      }
      if (mounted) {
        setState(() {
          _photo = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Choose a JPEG or PNG selfie smaller than 1 MB.',
        );
      }
    }
  }

  Future<void> _enter() async {
    if (_name.text.trim().isEmpty ||
        _photo == null ||
        !_consent ||
        (_join ? _code(_invite.text).isEmpty : _topic.text.trim().isEmpty)) {
      setState(
        () => _error =
            'Add your name, selfie and ${_join ? 'invitation' : 'case topic'}, then confirm sharing.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse(
              BackendAccess.instance.url(_join ? 'rooms/join' : 'rooms/create'),
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': _name.text.trim(),
              'image_base64': _photo!.split(',').last,
              'consent': true,
              if (_join)
                'code': _code(_invite.text)
              else
                'topic': _topic.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 60));
      final session = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      if (response.statusCode != 200) {
        throw Exception(session['error'] ?? 'Could not enter this room.');
      }
      if (_join) session['invite'] = _code(_invite.text);
      session['host'] = !_join;
      await widget.preferences.setString(_sessionKey, jsonEncode(session));
      await _activate(session);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store?.dispose();
    _name.dispose();
    _topic.dispose();
    _invite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_open && _store != null) {
      return SharedCourt(
        store: _store!,
        caseId: 'hearing',
        roomInvite: _session?['host'] == true
            ? '${Uri.base.replace(fragment: '')}#invite=${_session!['invite']}'
            : null,
        onLobby: () => setState(() => _open = false),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CoupleCourtBrand(),
                  TextButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CourtroomPreview(preferences: widget.preferences),
                      ),
                    ),
                    icon: const Icon(Icons.sports_esports_outlined),
                    label: const Text('Preview Metherapy'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _join
                        ? 'Your Metherapy session is ready.'
                        : 'Talk it through in Metherapy.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No account needed. Enter your name, add a selfie and invite your partner to a private two-person Metherapy session.',
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Create a room')),
                      ButtonSegment(value: true, label: Text('Join a room')),
                    ],
                    selected: {_join},
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(() => _join = v.single),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _name,
                    maxLength: 50,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 12),
                  if (_join)
                    TextField(
                      controller: _invite,
                      decoration: const InputDecoration(
                        labelText: 'Private invite link or code',
                      ),
                    )
                  else
                    TextField(
                      controller: _topic,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'What would you like to talk about together?',
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_photo != null)
                    Center(
                      child: ClipOval(
                        child: photoImage(
                          _photo!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      _photo == null ? 'Upload my selfie' : 'Change my selfie',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _consent = v ?? false),
                    title: const Text(
                      'I am 18+ and agree to the terms. This is my selfie and I agree to share it with the other person in this room. Optional Meta AI uploads require another confirmation.',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _enter,
                    child: Text(
                      _busy
                          ? 'Opening room…'
                          : _join
                          ? 'Join the Metherapy session'
                          : 'Create Metherapy session',
                    ),
                  ),
                  if (_store != null)
                    TextButton(
                      onPressed: () => setState(() => _open = true),
                      child: const Text('Return to my current room'),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Invitations expire after 24 hours and admit one partner. Room sessions last 7 days. Keep this browser’s site data to return; clearing it can lose your seat. Each room shares up to 8 AI actions and 1 artwork generation, subject to the demo’s remaining allowance. Outcomes are voluntary suggestions.',
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => LegalPage.open(context, 'terms'),
                        child: const Text('Terms'),
                      ),
                      TextButton(
                        onPressed: () => LegalPage.open(context, 'privacy'),
                        child: const Text('Privacy'),
                      ),
                      TextButton(
                        onPressed: () => LegalPage.open(context, 'help'),
                        child: const Text('Help'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
