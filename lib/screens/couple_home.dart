import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../localization/closer_localizations.dart';
import 'shared_court.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/cloud_couple_store.dart';
import 'live_couple_map.dart';
import 'camera_capture_screen.dart';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import '../models/couple_store.dart';
import 'court_experience.dart';
import 'couple_map.dart';
import 'room_chat.dart';
import '../services/photo_media.dart';
import '../services/notification_service.dart';

class CoupleHome extends StatefulWidget {
  const CoupleHome({super.key, required this.store});
  final CoupleStore store;
  @override
  State<CoupleHome> createState() => _CoupleHomeState();
}

class _CoupleHomeState extends State<CoupleHome> {
  int _tab = 0;
  bool _picking = false;
  bool _showDistanceBanner = true;
  String? _lastDistanceBand;
  DateTime? _lastDistanceNotificationAt;
  Map<String, dynamic>? _replyTo;
  final _message = TextEditingController();
  final _scroll = ScrollController();
  CoupleStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_handleDistanceChange);
    unawaited(NotificationService.instance.init());
  }

  double? _distanceMeters() {
    final cloud = store;
    if (cloud is! CloudCoupleStore || cloud.partnerUid == null) return null;
    final locations = cloud.locations;
    final mine = locations[cloud.uid], partner = locations[cloud.partnerUid];
    if (mine is! Map ||
        partner is! Map ||
        mine['lat'] is! num ||
        mine['lon'] is! num ||
        partner['lat'] is! num ||
        partner['lon'] is! num) {
      return null;
    }
    return Geolocator.distanceBetween(
      (mine['lat'] as num).toDouble(),
      (mine['lon'] as num).toDouble(),
      (partner['lat'] as num).toDouble(),
      (partner['lon'] as num).toDouble(),
    );
  }

  void _handleDistanceChange() {
    final meters = _distanceMeters();
    if (meters == null) {
      _lastDistanceBand = null;
      unawaited(NotificationService.instance.clearDistanceNotification());
      return;
    }
    final distance = meters < 1000
        ? '${meters.round()} m apart'
        : '${(meters / 1000).toStringAsFixed(1)} km apart';
    final now = DateTime.now();
    if (_lastDistanceBand == distance ||
        (_lastDistanceNotificationAt != null &&
            now.difference(_lastDistanceNotificationAt!) <
                const Duration(seconds: 30)))
      return;
    _lastDistanceBand = distance;
    _lastDistanceNotificationAt = now;
    unawaited(
      NotificationService.instance.showPartnerDistance(
        store.partnerName.isEmpty ? 'Your partner' : store.partnerName,
        distance,
      ),
    );
  }

  Future<void> _remindPartnerToShareLocation() async {
    try {
      await store.addMessage(
        'Location reminder: please share your location when you’re comfortable. You can turn it on in Closer Settings.',
      );
      _notice('Location reminder sent in chat.');
    } catch (_) {
      _notice('Could not send the location reminder. Please retry.');
    }
  }

  Widget _chatDistanceBanner() {
    final cloud = store is CloudCoupleStore ? store as CloudCoupleStore : null;
    final meters = _distanceMeters();
    final partner = cloud == null || cloud.partnerUid == null
        ? null
        : cloud.locations[cloud.partnerUid];
    final partnerShared =
        partner is Map && partner['lat'] is num && partner['lon'] is num;
    final partnerName = store.partnerName.isEmpty
        ? 'Your partner'
        : store.partnerName;
    final text = meters != null
        ? '$partnerName is ${meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km'} away'
        : partnerShared
        ? 'Your location is not shared yet'
        : '$partnerName has not shared a location';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD9C8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me_rounded, color: Color(0xFFE77A5E), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (!partnerShared && cloud != null)
            TextButton(
              onPressed: _remindPartnerToShareLocation,
              child: Text(tr('Remind')),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('Hide distance'),
            onPressed: () => setState(() => _showDistanceBanner = false),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _chatSuggestions(double? meters) {
    final suggestions = meters == null
        ? ["How’s your day going?", 'Miss you!', 'Send me a photo?']
        : meters < 500
        ? [
            "You’re super close! Want to meet up?",
            'Grab a drink together?',
            'Look behind you! 👋',
          ]
        : meters < 5000
        ? ["How’s it going over there?", 'Bring home dinner?', 'See you soon!']
        : [
            'Safe travels!',
            'Thinking of you from afar 💛',
            'Call me when you’re free!',
          ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(suggestion),
                onPressed: () {
                  _message.text = suggestion;
                  _message.selection = TextSelection.collapsed(
                    offset: suggestion.length,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    store.removeListener(_handleDistanceChange);
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _profile() async {
    if (store.online) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(
          title: tr('Your Closer profile'),
          label: tr('Your name'),
          description: 'Your partner chooses their own name on their phone.',
          action: 'Save name',
        ),
      );
      if (name == null || !mounted) return;
      try {
        store.yourName = name;
        await store.save();
      } catch (_) {
        _notice('Could not save your name. Please retry.');
      }
      return;
    }
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

  Future<String?> _uploadAvatar() async {
    if (store is! CloudCoupleStore) {
      _notice('Profile photos need an online paired account.');
      return null;
    }
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 82,
    );
    if (image == null) return null;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 88,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop profile photo',
            toolbarColor: const Color(0xFFFFE9DA),
            toolbarWidgetColor: const Color(0xFF663621),
            activeControlsWidgetColor: const Color(0xFFF18F77),
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
          ),
          IOSUiSettings(
            title: tr('Crop profile photo'),
            aspectRatioLockEnabled: false,
          ),
        ],
      );
      if (cropped == null || !mounted) return null;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Use this profile photo?')),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: photoImage(
              cropped.path,
              width: 240,
              height: 240,
              fit: BoxFit.cover,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Choose again')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Confirm photo')),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return null;
      final path = await savePickedPhoto(
        XFile(cropped.path),
        folderName: 'closer_avatar',
      );
      final cloud = store as CloudCoupleStore;
      await cloud.saveAvatar(path);
      if (mounted) setState(() {});
      return cloud.avatarPath;
    } catch (error) {
      _notice(
        'Profile photo could not be saved: ${error.toString().replaceFirst('Exception: ', '')}',
      );
      return null;
    }
  }

  Future<void> _summon() async {
    if (!store.hasProfile) {
      await _profile();
      if (!store.hasProfile || !mounted) return;
    }
    final issue = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: tr('Invite your partner to a Metherapy session'),
        label: tr('Session topic'),
        hint: tr('What would you like to work through together?'),
        description: 'Your partner sees this topic before joining the session.',
        action: 'Invite to session',
      ),
    );
    if (issue == null || !mounted) return;
    await store.addMessage(
      issue,
      summons: true,
      therapyLanguage: store is CloudCoupleStore
          ? (store as CloudCoupleStore).therapyLanguage
          : 'en',
    );
    if (mounted) setState(() => _tab = 4);
  }

  Future<void> _openCourt(Map<String, dynamic> message) async {
    if (message['status'] == 'closed') {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Session ended')),
          content: Text(
            tr('This Metherapy session is finished and can’t be re-entered.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('Got it')),
            ),
          ],
        ),
      );
      return;
    }
    if (store is CloudCoupleStore) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SharedCourt(
            store: store as CloudCoupleStore,
            caseId: message['id'] as String,
          ),
        ),
      );
      await (store as CloudCoupleStore).refresh();
      return;
    }
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
        builder: (_) => _TextDialog(
          title: tr('A photo for your conversation'),
          label: tr('Caption (optional)'),
          description: 'This photo will be shared with your paired partner.',
          action: 'Add to chat',
          allowEmpty: true,
        ),
      );
      if (caption == null || !mounted) return;
      final path = await savePickedPhoto(image, folderName: 'closer_chat');
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
              child: photoImage(
                path,
                errorBuilder: (_, error, stack) => Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(tr('Photo unavailable on this device.')),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Close')),
          ),
        ],
      ),
    ),
  );

  Widget _chatEntry(Map<String, dynamic> entry) => Align(
    alignment: entry['sender'] == 'partner'
        ? Alignment.centerLeft
        : Alignment.centerRight,
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
                child: photoImage(
                  entry['photoPath'] as String,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => SizedBox(
                    height: 100,
                    child: Center(child: Text(tr('Photo unavailable'))),
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
                '${_timeLabel(entry['createdAt'] as String?)} · ${store.online ? 'Sent' : 'Local only'}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF775B50)),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: tr('Message options'),
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
                  PopupMenuItem(value: 'reply', child: Text(tr('Reply'))),
                  PopupMenuItem(
                    value: 'heart',
                    child: Text(
                      (entry['heartedByMe'] ?? entry['hearted']) == true
                          ? 'Remove heart'
                          : 'Add a heart',
                    ),
                  ),
                  if ((entry['text'] as String).isNotEmpty)
                    PopupMenuItem(value: 'copy', child: Text(tr('Copy text'))),
                ],
              ),
            ],
          ),
          if (entry['hearted'] == true)
            Text(
              tr('♥'),
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
        builder: (_) => _TextDialog(
          title: tr('A moment worth keeping'),
          label: tr('Write a caption'),
          description: 'This memory will be shared with your paired partner.',
          action: 'Keep memory',
        ),
      );
      if (caption == null || !mounted) return;
      final path = await savePickedPhoto(image, folderName: 'couple_memories');
      if (!mounted) return;
      await store.addMemory(path, caption);
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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded, size: 38, color: peach),
              SizedBox(height: 16),
              Text(
                tr('Your little updates'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text(
                tr(
                  'Get new message and saved-place alerts, plus a quiet distance update while both of you share location.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  final service = NotificationService.instance;
                  final enabled = await service.isEnabled();
                  var granted = true;
                  if (enabled) {
                    if (store is CloudCoupleStore) {
                      try {
                        await (store as CloudCoupleStore).unregisterPushToken();
                      } catch (_) {
                        _notice(
                          'Could not turn off push alerts. Please retry.',
                        );
                        return;
                      }
                    }
                    await service.disable();
                  } else {
                    granted = await service.enable();
                    if (granted && store is CloudCoupleStore) {
                      try {
                        await (store as CloudCoupleStore).registerPushToken();
                      } catch (_) {
                        _notice(
                          'Distance updates are enabled, but push registration failed. Please retry.',
                        );
                      }
                    }
                    _lastDistanceBand = null;
                    _lastDistanceNotificationAt = null;
                    _handleDistanceChange();
                  }
                  if (context.mounted) Navigator.pop(context);
                  _notice(
                    enabled
                        ? 'Notifications turned off.'
                        : granted
                        ? 'Notifications are on.'
                        : 'Notification permission was not granted.',
                  );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(tr('Manage notifications')),
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
    builder: (context, _) => Container(
      decoration: _tab == 1
          ? const BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  'assets/branding/dreamy_peach_gradient_waves.png',
                ),
                fit: BoxFit.cover,
              ),
            )
          : null,
      child: Scaffold(
        backgroundColor: _tab == 1 ? Colors.transparent : null,
        extendBody: _tab == 0 || _tab == 2,
        appBar: null,
        bottomNavigationBar: CoupleDock(
          selected: _tab,
          onSelected: (index) => setState(() => _tab = index),
        ),
        body: Stack(
          children: [
            Offstage(
              offstage: _tab != 0,
              child: store is CloudCoupleStore
                  ? LiveCoupleMap(
                      store: store as CloudCoupleStore,
                      onProfile: _profile,
                      onDate: _date,
                      onAvatar: _uploadAvatar,
                      onNotifications: _notifications,
                    )
                  : CoupleMap(
                      yourName: store.yourName,
                      partnerName: store.partnerName,
                      startedOn: store.relationshipStart,
                      onProfile: _profile,
                      onDate: _date,
                      onNotifications: _notifications,
                    ),
            ),
            if (_tab != 0)
              _tab == 2
                  ? CameraCaptureScreen(
                      store: store,
                      onClose: () => setState(() => _tab = 0),
                    )
                  : SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            children: [
                              if (!store.online)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 9,
                                  ),
                                  color: const Color(0xFFFFEADB),
                                  child: Text(
                                    tr(
                                      'LOCAL PREVIEW · No account or partner connection yet',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: slate,
                                    ),
                                  ),
                                ),
                              if (store.storageError != null)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    store.storageError!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: switch (_tab) {
                                  1 => _court(),
                                  3 => _memories(),
                                  4 =>
                                    store is CloudCoupleStore
                                        ? RoomChat(
                                            store: store as CloudCoupleStore,
                                            onAttach: _attachChatPhoto,
                                            onInvite: _summon,
                                            sessionBuilder: _summonsCard,
                                          )
                                        : _chat(),
                                  _ => _home(),
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
          ],
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
      if (store.online)
        OutlinedButton.icon(
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
          icon: const Icon(Icons.logout),
          label: Text(tr('Sign out')),
        ),
      _heading(
        store.hasProfile
            ? '${store.yourName} & ${store.partnerName}'
            : 'A little closer, every day.',
        'Closer — your conversations, your memories, your space.',
      ),
      OutlinedButton.icon(
        onPressed: _date,
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(tr('Our anniversary')),
      ),
      const SizedBox(height: 16),
      _card(
        Icons.link,
        store.hasProfile ? 'Your profile' : 'One connection. A shared space.',
        'Your accounts are paired. Messages and memories sync with your partner; no rooms to recreate.',
        action: FilledButton(
          onPressed: _profile,
          child: Text(
            store.hasProfile ? tr('Edit your name') : tr('Set your name'),
          ),
        ),
      ),

      _card(
        Icons.near_me_outlined,
        'Distance, when you both choose.',
        'Open Map to share your real location. Each partner opts in separately; last-known updates show when they were captured.',
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
        Icons.auto_awesome_rounded,
        'Make room for understanding.',
        'Make space to hear each other with a guided Metherapy session.',
        action: OutlinedButton(
          onPressed: _summon,
          child: Text(tr('Invite partner to a session')),
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
            if (!_showDistanceBanner)
              IconButton(
                onPressed: () => setState(() => _showDistanceBanner = true),
                icon: const Icon(Icons.near_me_outlined),
                tooltip: tr('Show shared distance'),
              ),
            IconButton(
              onPressed: _summon,
              icon: const Icon(Icons.auto_awesome_rounded),
              tooltip: tr('Invite partner to a session'),
            ),
          ],
        ),
      ),
      if (_showDistanceBanner) _chatDistanceBanner(),
      _chatSuggestions(_distanceMeters()),
      Expanded(
        child: store.messages.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    tr(
                      'Your story starts here.\nSend your partner a message, photo or Metherapy invite.',
                    ),
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
                tooltip: tr('Cancel reply'),
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
              tooltip: tr('Attach chat photo'),
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _message,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: tr('Write a message…'),
                  counterText: '',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.arrow_upward),
              tooltip: tr('Send message'),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    final text = _message.text;
    try {
      await store.addMessage(text, replyTo: _replyTo);
      if (!mounted) return;
      _message.clear();
    } catch (_) {
      _notice('Message was not sent. Check your connection and retry.');
      return;
    }
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
              const Icon(Icons.auto_awesome_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry['status'] == 'closed'
                      ? entry['courtStatus'] == 'ended'
                            ? 'Session · ended'
                            : entry['courtStatus'] == 'unresolved'
                            ? 'Session · unfinished'
                            : 'Session · complete'
                      : 'A guided session together?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(entry['text'] as String),
          const SizedBox(height: 12),
          if (entry['status'] == 'closed')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((entry['agreement'] as String? ?? '').isNotEmpty)
                  Text('Our next step: ${entry['agreement']}'),
                const SizedBox(height: 4),
                Text(
                  tr('This session has ended and can’t be re-entered.'),
                  style: TextStyle(fontSize: 12, color: Color(0xFF80665D)),
                ),
              ],
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFBE92), Color(0xFFF6759E)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _openCourt(entry),
                child: Text(
                  tr('Enter Metherapy session'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (!store.online)
            Text(
              tr('Local preview · partner has not been notified'),
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
        label: Text(_picking ? tr('Adding photo…') : tr('Add a memory')),
      ),
      const SizedBox(height: 20),
      if (store.memories.isEmpty)
        _card(
          Icons.photo_camera_outlined,
          'Your first memory is waiting.',
          'Choose a photo and add a caption to your shared album.',
        ),
      for (final memory in store.memories)
        Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              photoImage(
                memory['path'] as String,
                height: 280,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(tr('Photo unavailable on this device')),
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

  Future<void> _showAllSessions(
    List<Map<String, dynamic>> cases,
    List<Map<String, dynamic>> history,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF9F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('All sessions'),
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(
                              color: const Color(0xFF542819),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      tooltip: tr('Close'),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in cases)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _summonsCard(entry),
                        ),
                      for (final record in history)
                        ListTile(
                          leading: const Icon(
                            Icons.history_rounded,
                            color: Color(0xFFB85F41),
                          ),
                          title: Text(
                            record['topic'] as String? ??
                                tr('Previous session'),
                          ),
                          subtitle: Text(
                            '${record['agreement'] ?? 'Session ended'} · ${record['practice'] == true ? 'Practice' : 'Metherapy'}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _court() {
    final cases = store.messages
        .where((message) => message['kind'] == 'court')
        .toList();
    DateTime sessionDate(Map<String, dynamic> item) {
      final value = item['createdAt'];
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
      }
      return DateTime.tryParse(value?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    cases.sort((a, b) => sessionDate(b).compareTo(sessionDate(a)));
    final history = store.courtHistory
        .where(
          (record) => !store.messages.any(
            (message) =>
                message['recordId'] != null &&
                message['recordId'] == record['id'],
          ),
        )
        .toList();
    history.sort((a, b) => sessionDate(b).compareTo(sessionDate(a)));
    final sessionCount = cases.length + history.length;

    Widget historyTile(Map<String, dynamic> record) => ListTile(
      contentPadding: const EdgeInsets.only(left: 50, right: 0),
      leading: const Icon(Icons.history, color: Color(0xFFB85F41)),
      title: Text(record['topic'] as String? ?? tr('Previous session')),
      subtitle: Text(
        '${record['agreement'] ?? 'Session ended'} · ${record['practice'] == true ? 'Practice' : 'Metherapy'}',
      ),
      isThreeLine: false,
    );

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Metherapy'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF542819),
                              fontWeight: FontWeight.w800,
                              fontSize: 34,
                            ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 10),
                        width: 260,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB99D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Text(
                        tr('A softer space to understand each other.'),
                        style: TextStyle(
                          fontSize: 17,
                          color: Color(0xFF663621),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.favorite_border_rounded,
                    size: 45,
                    color: Color(0xFFEF8057),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.fromLTRB(26, 25, 26, 26),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .76),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .82),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18B76140),
                    blurRadius: 22,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFFFB17E), Color(0xFFF44F86)],
                        ).createShader(bounds),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 58,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: tr('About Metherapy'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(tr('A guided conversation')),
                            content: Text(
                              tr(
                                'Metherapy offers supportive prompts and reflections. It is not a licensed therapist or clinical care. Write a topic before inviting your partner. Both partners agree before context is sent to Meta. Take turns speaking, then hear a reflection and choose a next step together.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(tr('Close')),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          size: 34,
                          color: Color(0xFFF17F65),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr('Speak. Listen. Find a next step.'),
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF542819),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .12).clamp(
                      60.0,
                      150.0,
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB77F), Color(0xFFF34D86)],
                        ),
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x30E66D45),
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(36),
                          onTap: _summon,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 17,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    tr('Invite partner to a session'),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .78),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .84),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Previous sessions'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: const Color(0xFF542819),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('See all'),
                        onPressed: () => _showAllSessions(cases, history),
                        icon: const Icon(
                          Icons.history_rounded,
                          size: 34,
                          color: Color(0xFFF27195),
                        ),
                      ),
                    ],
                  ),
                  if (sessionCount == 0)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        tr(
                          'No sessions yet. Start with one thing you would like to understand together.',
                        ),
                        style: TextStyle(color: Color(0xFF663621)),
                      ),
                    ),
                  if (cases.isNotEmpty)
                    _summonsCard(cases.first)
                  else if (history.isNotEmpty)
                    historyTile(history.first),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
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
    title: Text(tr('Your preview profile')),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'These names are saved locally. This does not create accounts or pair two phones.',
              ),
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
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, [_you.text.trim(), _partner.text.trim()]);
          }
        },
        child: Text(tr('Save names')),
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
    this.hint,
    this.allowEmpty = false,
  });
  final String title, label, description, action;
  final String? hint;
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
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                alignLabelWithHint: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
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
        child: Text(tr('Cancel')),
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
