import 'legal_page.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'couple_map.dart' show ivory, peach;
import '../localization/closer_localizations.dart';
import '../services/photo_media.dart';

class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({
    super.key,
    required this.yourName,
    required this.partnerName,
    required this.sharing,
    required this.busy,
    required this.onProfile,
    required this.onNotifications,
    required this.onShareChanged,
    required this.avatarPath,
    required this.onAvatar,
    required this.therapyLanguage,
    required this.onTherapyLanguageChanged,
    required this.canManageAccount,
    required this.onSignOut,
    required this.onUnpair,
  });

  final String yourName, partnerName;
  final bool sharing, busy;
  final VoidCallback onProfile, onNotifications;
  final Future<bool> Function(bool) onShareChanged;
  final String? avatarPath;
  final Future<String?> Function() onAvatar;
  final String therapyLanguage;
  final Future<void> Function(String) onTherapyLanguageChanged;
  final bool canManageAccount;
  final Future<void> Function() onSignOut, onUnpair;

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  late bool _sharing;
  bool _busy = false, _languageBusy = false;
  String? _avatar;
  late String _therapyLanguage;

  static const _languages = <String, String>{
    'en': 'English',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'hi': 'हिन्दी',
    'fil': 'Filipino',
  };
  static const _shortLanguages = <String, String>{
    'en': 'English',
    'id': 'Indonesia',
    'ms': 'Melayu',
    'hi': 'हिन्दी',
    'fil': 'Filipino',
  };

  @override
  void initState() {
    super.initState();
    _sharing = widget.sharing;
    _avatar = widget.avatarPath;
    _therapyLanguage = _languages.containsKey(widget.therapyLanguage)
        ? widget.therapyLanguage
        : 'en';
  }

  Future<void> _toggleSharing(bool enabled) async {
    setState(() => _busy = true);
    try {
      final actual = await widget.onShareChanged(enabled);
      if (mounted) setState(() => _sharing = actual);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeAvatar() async {
    final path = await widget.onAvatar();
    if (mounted && path != null) setState(() => _avatar = path);
  }

  @override
  Widget build(BuildContext context) {
    final partnerLabel = widget.partnerName.isEmpty
        ? 'your partner'
        : widget.partnerName;
    return Scaffold(
      backgroundColor: const Color(0xFFFFE9DA),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(top: -130, left: -85, child: _wash(300)),
            Positioned(bottom: -190, right: -70, child: _wash(340)),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 34),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF773A27),
                      size: 30,
                    ),
                    tooltip: tr('Close settings'),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _changeAvatar,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: peach,
                            child: _avatar == null
                                ? Text(
                                    widget.yourName.isEmpty
                                        ? '?'
                                        : widget.yourName.characters.first
                                              .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : ClipOval(
                                    child: photoImage(
                                      _avatar!,
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 31,
                              height: 31,
                              decoration: BoxDecoration(
                                color: const Color(0xFFED835F),
                                shape: BoxShape.circle,
                                border: Border.all(color: ivory, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Text(
                        widget.yourName.isEmpty
                            ? 'Your profile'
                            : widget.yourName,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF663621),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                _group([
                  _row(
                    Icons.badge_outlined,
                    'My profile',
                    onTap: widget.onProfile,
                  ),
                  _row(
                    Icons.people_alt_outlined,
                    "Partner’s profile",
                    trailing: widget.partnerName.isEmpty
                        ? 'Not paired'
                        : widget.partnerName,
                    onTap: () => _info(
                      context,
                      'Partner profile',
                      widget.partnerName.isEmpty
                          ? 'Pair with your partner to see their profile here.'
                          : 'Your partner appears as ${widget.partnerName}.',
                    ),
                  ),
                  _row(
                    Icons.notifications_none_rounded,
                    'Notifications',
                    onTap: widget.onNotifications,
                  ),
                  _row(
                    Icons.language_rounded,
                    'Language',
                    trailing: _shortLanguages[_therapyLanguage] ?? 'English',
                    onTap: _chooseTherapyLanguage,
                  ),
                  _row(
                    Icons.shield_outlined,
                    'Permissions',
                    onTap: () => _permissions(context),
                  ),
                ]),
                const SizedBox(height: 18),
                _group([
                  _row(
                    Icons.layers_outlined,
                    'App theme',
                    onTap: () => _info(
                      context,
                      'App theme',
                      'Closer uses its peach theme.',
                    ),
                  ),
                  _row(
                    Icons.lock_outline_rounded,
                    'Privacy & Security',
                    onTap: () => LegalPage.open(context, 'privacy'),
                  ),
                ]),
                if (widget.canManageAccount) ...[
                  const SizedBox(height: 18),
                  _group([
                    _row(Icons.logout_rounded, 'Sign out', onTap: _signOut),
                    _row(
                      Icons.link_off_rounded,
                      'Unpair from partner',
                      onTap: _confirmUnpair,
                    ),
                  ]),
                ],
                const SizedBox(height: 18),
                _group([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: peach,
                          size: 29,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            tr('Share my location'),
                            style: TextStyle(
                              fontSize: 17,
                              color: Color(0xFF663621),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: _sharing,
                          onChanged: _busy || widget.busy
                              ? null
                              : _toggleSharing,
                          activeTrackColor: peach,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(65, 0, 20, 16),
                    child: Text(
                      _busy || widget.busy
                          ? 'Connecting to your location…'
                          : _sharing
                          ? 'Sharing with $partnerLabel, even when Closer is in the background. The system shows an ongoing indicator.'
                          : 'Off. Turn this on when you want your paired partner to see your location.',
                      style: const TextStyle(
                        color: Color(0xFF745B50),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 64, endIndent: 18),
                  _row(
                    Icons.settings_outlined,
                    'Phone location permission',
                    trailing: 'Manage',
                    onTap: Geolocator.openAppSettings,
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseTherapyLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: ivory,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('App language'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF663621),
                  ),
                ),
              ),
            ),
            for (final entry in _languages.entries)
              ListTile(
                title: Text(entry.value),
                trailing: _therapyLanguage == entry.key
                    ? const Icon(Icons.check_rounded, color: peach)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null || selected == _therapyLanguage) return;
    final previous = _therapyLanguage;
    setState(() {
      _therapyLanguage = selected;
      _languageBusy = true;
    });
    try {
      await widget.onTherapyLanguageChanged(selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trParams(
                'Closer and new Metherapy sessions will use {language}.',
                {'language': _languages[selected]!},
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _therapyLanguage = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save language: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _languageBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_languageBusy || _busy) return;
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not sign out: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmUnpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Unpair from your partner?')),
        content: Text(
          tr(
            'Both accounts will be unpaired and will lose access to this shared space, including its synced messages, memories, locations and sessions. The saved records are retained by Closer but will no longer be available to either account through this pairing.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Keep pairing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Unpair')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _languageBusy = true);
    try {
      await widget.onUnpair();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not unpair: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _languageBusy = false);
    }
  }

  Widget _wash(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [Color(0xFFFFC5A4), Color(0x00FFC5A4)]),
    ),
  );

  Widget _group(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: ivory.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18AA654A),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );

  Widget _row(
    IconData icon,
    String label, {
    String? trailing,
    required VoidCallback onTap,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    leading: Icon(icon, color: peach, size: 30),
    title: Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        color: Color(0xFF663621),
        fontWeight: FontWeight.w500,
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null)
          Text(trailing, style: const TextStyle(color: Color(0xFF9A6653))),
        const SizedBox(width: 8),
        const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFC4775F),
          size: 28,
        ),
      ],
    ),
    onTap: onTap,
  );

  Future<void> _permissions(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: ivory,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Location permissions'),
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF663621),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Location sharing is optional and controlled by the switch in Settings. To keep sharing while the app is closed, set Closer’s phone permission to “Allow all the time.” You can change or remove that permission in your phone settings.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.openAppSettings();
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(tr('Open phone settings')),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _info(BuildContext context, String title, String body) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Done')),
            ),
          ],
        ),
      );
}
