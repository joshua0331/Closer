import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cloud_couple_store.dart';
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _sharing) {
      _stop();
    }
  }

  Future<void> _stop() async {
    await _position?.cancel();
    _position = null;
    if (mounted) setState(() => _sharing = false);
    try {
      await widget.store.shareLocation(null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not remove the last location yet. Reconnect and tap Pause again.',
        );
      }
    }
  }

  Future<void> _start() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share your location?'),
        content: const Text(
          'Your paired partner can see your position while this map is open. Sharing pauses when the app backgrounds. You can stop at any time. Your partner’s location appears only if they choose to share too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share location'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on device location services first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is off. Enable it in device settings to share.',
        );
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (!mounted) return;
      await _send(current);
      _map.move(LatLng(current.latitude, current.longitude), 13);
      if (!mounted) return;
      setState(() => _sharing = true);
      _position =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 50,
            ),
          ).listen(
            (p) async {
              if (_lastSent == null ||
                  DateTime.now().difference(_lastSent!).inSeconds >= 20) {
                try {
                  await _send(p);
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => _error = 'Location update failed. Your partner sees the last update.',
                    );
                  }
                }
              }
            },
            onError: (_) {
              if (mounted) {
                setState(
                  () => _error =
                      'Location updates stopped. Pause and try sharing again.',
                );
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(Position p) async {
    await widget.store.shareLocation({'lat': p.latitude, 'lon': p.longitude});
    _lastSent = DateTime.now();
  }

  LatLng? point(dynamic item) {
    if (item is! Map || item['lat'] is! num || item['lon'] is! num) return null;
    return LatLng(
      (item['lat'] as num).toDouble(),
      (item['lon'] as num).toDouble(),
    );
  }

  String updated(dynamic item) {
    final date = DateTime.tryParse(
      item is Map ? item['updatedAt'] as String? ?? '' : '',
    );
    if (date == null) return '';
    final minutes = DateTime.now().difference(date).inMinutes;
    return minutes < 1 ? 'just now' : '$minutes min ago';
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store, locations = widget.store.locations;
    final me = point(locations[store.uid]),
        partner = point(locations[store.partnerUid]);
    final distance = me == null || partner == null
        ? null
        : Geolocator.distanceBetween(
                me.latitude,
                me.longitude,
                partner.latitude,
                partner.longitude,
              ) /
              1000;
    final anniversary = store.relationshipStart;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: me ?? partner ?? const LatLng(20, 0),
            initialZoom: me != null || partner != null ? 12 : 2,
            minZoom: 2,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: const String.fromEnvironment(
                'MAP_TILE_URL',
                defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              userAgentPackageName: 'com.jcm.closer',
              errorTileCallback: (tile, error, stack) {
                if (mounted && !_tileError) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tileError = true);
                  });
                }
              },
            ),
            if (me != null && partner != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [me, partner],
                    strokeWidth: 3,
                    color: peach,
                    pattern: const StrokePattern.dotted(),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (me != null) _marker(me, store.yourName, true),
                if (partner != null) _marker(partner, store.partnerName, false),
              ],
            ),
          ],
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 16,
          left: 16,
          right: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _round(Icons.settings_outlined, widget.onProfile, 'Profile'),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onDate,
                  child: Card(
                    color: ivory,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          const Icon(Icons.favorite_outline, color: peach),
                          Text(
                            anniversary == null ? 'Our story' : 'Together for',
                            style: const TextStyle(color: slate),
                          ),
                          Text(
                            anniversary == null
                                ? 'Add your anniversary'
                                : '${DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(anniversary)).inDays} days',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _round(Icons.my_location, () {
                if (me != null) {
                  _map.move(me, 15);
                } else {
                  _start();
                }
              }, 'My location'),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 135,
          child: Card(
            color: ivory,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    distance == null
                        ? 'Your places, together'
                        : '${distance.toStringAsFixed(1)} km apart · last known',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    partner == null
                        ? '${store.partnerName} has not shared a location.'
                        : '${store.partnerName} · updated ${updated(locations[store.partnerUid])}',
                  ),
                  if (_tileError)
                    const Text(
                      'Map tiles could not load. Check your connection, then reopen Map.',
                    ),
                  if (_error != null) Text(_error!),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : (_sharing)
                        ? _stop
                        : _start,
                    icon: Icon(
                      _sharing ? Icons.pause : Icons.location_on_outlined,
                    ),
                    label: Text(
                      _busy
                          ? 'Finding your location…'
                          : _sharing
                          ? 'Pause location sharing'
                          : 'Share my location',
                    ),
                  ),
                  if (!_sharing && me != null)
                    TextButton(
                      onPressed: _busy ? null : _stop,
                      child: const Text('Remove my last-known location'),
                    ),
                  const Text(
                    'Updates run while this map is open. Last-known positions remain until removed.',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 108,
          right: 10,
          child: GestureDetector(
            onTap: () =>
                launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            child: const ColoredBox(
              color: ivory,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 11, color: slate),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _round(IconData icon, VoidCallback action, String label) =>
      IconButton.filledTonal(
        onPressed: action,
        tooltip: label,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: ivory,
          foregroundColor: slate,
        ),
      );
  Marker _marker(LatLng point, String name, bool me) => Marker(
    point: point,
    width: 90,
    height: 82,
    child: Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: me ? peach : const Color(0xFF78AFA5),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 23, color: Colors.white),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: ivory,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: slate),
          ),
        ),
      ],
    ),
  );
}
