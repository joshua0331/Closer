import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cloud_couple_store.dart';
import 'location_settings_page.dart';
import 'couple_map.dart' show peach, ivory, slate;

class LiveCoupleMap extends StatefulWidget {
  const LiveCoupleMap({
    super.key,
    required this.store,
    required this.onProfile,
    required this.onDate,
  });
  final CloudCoupleStore store;
  final VoidCallback onProfile, onDate;
  @override
  State<LiveCoupleMap> createState() => _LiveCoupleMapState();
}

class _LiveCoupleMapState extends State<LiveCoupleMap>
    with WidgetsBindingObserver {
  final _map = MapController();
  StreamSubscription<Position>? _position;
  bool _sharing = false, _busy = false, _tileError = false;
  String? _error;
  DateTime? _lastSent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSharing());
  }

  Future<void> _restoreSharing() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_preferenceKey) == true && mounted) {
      await _start(askConsent: false);
    }
  }

  String get _preferenceKey => 'closer_location_share_${widget.store.uid}';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Location keeps running through the OS-managed foreground service / iOS
    // background location mode while the user has sharing enabled.
    if (state == AppLifecycleState.resumed && _sharing && _position == null) {
      _listenForPositions();
    }
  }

  Future<void> _stop() async {
    await _position?.cancel();
    _position = null;
    if (mounted) setState(() => _sharing = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, false);
    try {
      await widget.store.shareLocation(null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not clear the shared location. Reconnect and try again.');
    }
  }

  Future<void> _start({bool askConsent = true}) async {
    if (askConsent) {
      final consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share your location?'),
          content: const Text(
            'When enabled, your paired partner can see your location, including while Closer is in the background. A visible system indicator or notification will show while sharing. Turn it off any time in Settings.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (consent != true || !mounted) return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on device location services first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is off. Allow location in your phone settings to share.');
      }
      if (permission != LocationPermission.always) {
        if (mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Allow background location'),
              content: const Text('To keep sharing when Closer is closed or your screen is off, set Closer location access to “Allow all the time” in your phone settings. You can still choose when to share inside Closer.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open settings')),
              ],
            ),
          );
          if (openSettings == true) await Geolocator.openAppSettings();
        }
        throw Exception('Enable “Allow all the time” location access, then turn sharing on again.');
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
      );
      await _send(current);
      if (!mounted) return;
      _map.move(LatLng(current.latitude, current.longitude), 13);
      setState(() => _sharing = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, true);
      _listenForPositions();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LocationSettings _backgroundSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        intervalDuration: const Duration(seconds: 20),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Closer location sharing is on',
          notificationText: 'Your partner can see your location. Tap to open Closer.',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50);
  }

  void _listenForPositions() {
    if (_position != null) return;
    _position = Geolocator.getPositionStream(locationSettings: _backgroundSettings()).listen(
      (p) async {
        if (_lastSent == null || DateTime.now().difference(_lastSent!).inSeconds >= 20) {
          try { await _send(p); }
          catch (_) { if (mounted) setState(() => _error = 'Location update failed. Your partner sees the last update.'); }
        }
      },
      onError: (_) { if (mounted) setState(() => _error = 'Location updates stopped. Check your location permission and sharing settings.'); },
    );
  }

  Future<void> _send(Position p) async {
    await widget.store.shareLocation({'lat': p.latitude, 'lon': p.longitude});
    _lastSent = DateTime.now();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => LocationSettingsPage(
        yourName: widget.store.yourName,
        partnerName: widget.store.partnerName,
        sharing: _sharing,
        busy: _busy,
        onProfile: widget.onProfile,
        onShareChanged: (enabled) async {
          if (enabled) {
            await _start();
          } else {
            await _stop();
          }
          if (mounted) setState(() {});
          return _sharing;
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  LatLng? point(dynamic item) {
    if (item is! Map || item['lat'] is! num || item['lon'] is! num) return null;
    return LatLng((item['lat'] as num).toDouble(), (item['lon'] as num).toDouble());
  }

  String updated(dynamic item) {
    final date = DateTime.tryParse(item is Map ? item['updatedAt'] as String? ?? '' : '');
    if (date == null) return '';
    final minutes = DateTime.now().difference(date).inMinutes;
    return minutes < 1 ? 'just now' : '$minutes min ago';
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store, locations = widget.store.locations;
    final me = point(locations[store.uid]), partner = point(locations[store.partnerUid]);
    final distance = me == null || partner == null ? null : Geolocator.distanceBetween(me.latitude, me.longitude, partner.latitude, partner.longitude) / 1000;
    final anniversary = store.relationshipStart;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: me ?? partner ?? const LatLng(20, 0),
          initialZoom: me != null || partner != null ? 12 : 2,
          minZoom: 2,
          maxZoom: 19,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'com.jcm.closer',
            errorTileCallback: (tile, error, stack) { if (mounted && !_tileError) setState(() => _tileError = true); },
          ),
          if (me != null && partner != null) PolylineLayer(polylines: [Polyline(points: [me, partner], strokeWidth: 3, color: peach, pattern: const StrokePattern.dotted())]),
          MarkerLayer(markers: [if (me != null) _marker(me, store.yourName, true), if (partner != null) _marker(partner, store.partnerName, false)]),
        ],
      ),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 16, left: 16, right: 16,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _round(Icons.settings_outlined, _openSettings, 'Settings'), const SizedBox(width: 10),
          Expanded(child: GestureDetector(onTap: widget.onDate, child: Card(color: ivory, child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
            const Icon(Icons.favorite_outline, color: peach),
            Text(anniversary == null ? 'Our story' : 'Together for', style: const TextStyle(color: slate)),
            Text(anniversary == null ? 'Add your anniversary' : '${DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(anniversary)).inDays} days', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ]))))), const SizedBox(width: 10),
          _round(Icons.my_location, () {
            if (me != null) {
              _map.move(me, 15);
            } else {
              _openSettings();
            }
          }, 'Center map'),
        ]),
      ),
      if (_error != null || _tileError || distance != null || partner == null)
        Positioned(left: 20, right: 20, bottom: 112, child: Card(color: ivory, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (distance != null) Text('${distance.toStringAsFixed(1)} km apart · ${updated(locations[store.uid])}', style: const TextStyle(color: slate, fontWeight: FontWeight.w600)),
          if (partner == null) Text('${store.partnerName} has not shared a location.', textAlign: TextAlign.center, style: const TextStyle(color: slate)),
          if (_tileError) const Text('Map tiles could not load. Check your connection and reopen Map.', textAlign: TextAlign.center),
          if (_error != null) Text(_error!, textAlign: TextAlign.center),
        ])))),
      Positioned(bottom: 106, right: 10, child: GestureDetector(onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')), child: const ColoredBox(color: ivory, child: Padding(padding: EdgeInsets.all(4), child: Text('© OpenStreetMap · © CARTO', style: TextStyle(fontSize: 10, color: slate)))))),
    ]);
  }

  Widget _round(IconData icon, VoidCallback action, String label) => IconButton.filledTonal(onPressed: action, tooltip: label, icon: Icon(icon), style: IconButton.styleFrom(backgroundColor: ivory, foregroundColor: slate));

  Marker _marker(LatLng point, String name, bool me) => Marker(
    point: point, width: 90, height: 82,
    child: Column(children: [
      CircleAvatar(radius: 25, backgroundColor: me ? peach : const Color(0xFF78AFA5), child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 23, color: Colors.white))),
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: ivory, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: slate))),
    ]),
  );
}
