import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

import '../localization/closer_localizations.dart';
import '../models/cloud_couple_store.dart';
import 'couple_map.dart' show ivory, peach;

class SavedPlacesPage extends StatefulWidget {
  const SavedPlacesPage({
    super.key,
    required this.store,
    required this.initialCenter,
  });

  final CloudCoupleStore store;
  final gm.LatLng initialCenter;

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  List<Map<String, dynamic>> get _places =>
      (widget.store.couple?['savedPlaces'] as List? ?? [])
          .whereType<Map>()
          .map((place) => Map<String, dynamic>.from(place))
          .toList();

  Future<void> _addOrEdit([Map<String, dynamic>? place]) async {
    final partner = widget.store.locations[widget.store.partnerUid];
    final partnerCenter =
        partner is Map && partner['lat'] is num && partner['lon'] is num
        ? gm.LatLng(
            (partner['lat'] as num).toDouble(),
            (partner['lon'] as num).toDouble(),
          )
        : widget.initialCenter;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PlaceEditor(
          store: widget.store,
          center: place == null
              ? partnerCenter
              : gm.LatLng(
                  (place['lat'] as num).toDouble(),
                  (place['lon'] as num).toDouble(),
                ),
          existing: place,
        ),
      ),
    );
    if (saved == true) await widget.store.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _delete(Map<String, dynamic> place) async {
    final id = place['id'] as String?;
    if (id == null) return;
    try {
      await widget.store.action({'action': 'saved_place_delete', 'id': id});
      await widget.store.refresh();
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ivory,
    appBar: AppBar(
      title: Text(tr('Place Alert')),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        Text(
          tr('Saved places'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF292B2E),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr(
            'Choose places like Home, Work, or School. Closer can notify you when your partner arrives or leaves.',
          ),
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: _addOrEdit,
          icon: const Icon(Icons.add_circle_rounded),
          label: Text(tr('Add a new place')),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE98B72),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE98B72), width: 1.6),
            minimumSize: const Size.fromHeight(62),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_places.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              tr(
                'No saved places yet. Add one to set up an arrival or departure alert.',
              ),
            ),
          )
        else
          ..._places.map(_placeCard),
        const SizedBox(height: 12),
        Text(
          tr(
            'Place alerts are shared with your paired partner. Both of you need location sharing turned on. The app sends an alert when a new location update crosses a saved place boundary.',
          ),
          style: TextStyle(color: Colors.black54, height: 1.45),
        ),
      ],
    ),
  );

  Widget _placeCard(Map<String, dynamic> place) {
    final name = place['name'] as String? ?? 'Saved place';
    final addedBy = place['createdBy'] == widget.store.uid
        ? 'you'
        : widget.store.partnerName;
    final lat = (place['lat'] as num?)?.toDouble();
    final lon = (place['lon'] as num?)?.toDouble();
    final enabled = place['enabled'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _addOrEdit(place),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EE),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.place_rounded,
                    color: peach,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF292B2E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lat == null || lon == null
                            ? 'Added by $addedBy'
                            : 'Added by $addedBy · ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${place['notifyArrival'] == true ? 'Arrivals' : ''}${place['notifyArrival'] == true && place['notifyDeparture'] == true ? ' · ' : ''}${place['notifyDeparture'] == true ? 'Departures' : 'Alerts off'}',
                        style: TextStyle(
                          color: enabled
                              ? const Color(0xFFE98B72)
                              : Colors.black45,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('Place options'),
                  onSelected: (value) {
                    if (value == 'edit') _addOrEdit(place);
                    if (value == 'delete') _delete(place);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(tr('Edit alerts')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(tr('Remove place')),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      enabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      color: enabled ? const Color(0xFFE98B72) : Colors.black38,
                    ),
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

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({
    required this.store,
    required this.center,
    this.existing,
  });
  final CloudCoupleStore store;
  final gm.LatLng center;
  final Map<String, dynamic>? existing;

  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  late final TextEditingController _name;
  late gm.LatLng _point;
  gm.GoogleMapController? _map;
  final _search = TextEditingController();
  bool _searching = false;
  Future<void> _findPlace() async {
    if (_searching || _search.text.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await const MethodChannel('com.jcm.closer/place_search')
          .invokeListMethod<dynamic>('search', {'query': _search.text.trim()});
      if (!mounted) return;
      if (results == null || results.isEmpty)
        throw Exception('No matching place. Include city or country.');
      final selected = await showDialog<Map>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose a place'),
          children: results.map((raw) {
            final item = raw as Map;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Text(item['name'] as String),
            );
          }).toList(),
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _point = gm.LatLng(
          (selected['lat'] as num).toDouble(),
          (selected['lon'] as num).toDouble(),
        );
        if (_name.text.isEmpty) _name.text = _search.text.trim();
      });
      await _map?.animateCamera(gm.CameraUpdate.newLatLngZoom(_point, 16));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Place search unavailable or no match. Try a full address or mark the map.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  double _radius = 200;
  bool _arrives = true, _leaves = true, _enabled = true, _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?['name'] as String? ?? '');
    _point = existing == null
        ? widget.center
        : gm.LatLng(
            (existing['lat'] as num).toDouble(),
            (existing['lon'] as num).toDouble(),
          );
    _radius = (existing?['radiusMeters'] as num?)?.toDouble() ?? 200;
    _arrives = existing?['notifyArrival'] as bool? ?? true;
    _leaves = existing?['notifyDeparture'] as bool? ?? true;
    _enabled = existing?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _search.dispose();
    _map?.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Enter a name for this place.'))),
      );
      return;
    }
    if (!_arrives && !_leaves) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Choose arrivals, departures, or both.'))),
      );
      return;
    }
    setState(() => _saving = true);
    var notificationsReady = true;
    try {
      if (_enabled) notificationsReady = await _registerPush();
      final nowId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final existing = widget.existing;
      await widget.store.action({
        'action': 'saved_place_save',
        'place': {
          'id': existing?['id'] as String? ?? nowId,
          'name': name,
          'lat': _point.latitude,
          'lon': _point.longitude,
          'radiusMeters': _radius.round(),
          'notifyArrival': _arrives,
          'notifyDeparture': _leaves,
          'enabled': _enabled,
        },
      });
      if (!mounted) return;
      if (!notificationsReady) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Place saved')),
            content: Text(
              tr(
                'Allow Closer notifications and enable location sharing to receive arrival and departure alerts.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Got it')),
              ),
            ],
          ),
        );
        if (!mounted) return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<bool> _registerPush() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      await widget.store.registerPushToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF9F0),
    appBar: AppBar(
      title: Text(widget.existing == null ? tr('Add place') : tr('Edit place')),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      children: [
        Center(
          child: Text(
            widget.existing == null ? 'Add Place' : 'Edit Place',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF292B2E),
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _findPlace(),
          decoration: InputDecoration(
            labelText: 'Search place or address',
            suffixIcon: IconButton(
              onPressed: _searching ? null : _findPlace,
              icon: Icon(_searching ? Icons.hourglass_top : Icons.search),
            ),
          ),
        ),
        Text(
          '${_point.latitude.toStringAsFixed(5)}, ${_point.longitude.toStringAsFixed(5)}',
        ),
        TextField(
          controller: _name,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: tr('Place name'),
            hintText: tr('Home, Work, School'),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Tap the map to move the alert area.'),
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 230,
            child: gm.GoogleMap(
              onMapCreated: (controller) => _map = controller,
              initialCameraPosition: gm.CameraPosition(
                target: _point,
                zoom: 16,
                tilt: 0,
              ),
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              circles: {
                gm.Circle(
                  circleId: const gm.CircleId('radius'),
                  center: _point,
                  radius: _radius,
                  fillColor: const Color(0x33F18F77),
                  strokeColor: const Color(0xFFE98B72),
                  strokeWidth: 2,
                ),
              },
              markers: {
                gm.Marker(
                  markerId: const gm.MarkerId('place'),
                  position: _point,
                ),
              },
              onTap: (point) => setState(() => _point = point),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Alert radius'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text('${_radius.round()} m'),
          ],
        ),
        Slider(
          value: _radius,
          min: 50,
          max: 1000,
          divisions: 19,
          activeColor: const Color(0xFFE98B72),
          onChanged: (value) => setState(() => _radius = value),
        ),
        const SizedBox(height: 4),
        Text(
          'Notify me when ${widget.store.partnerName.isEmpty ? 'my partner' : widget.store.partnerName}…',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _alertSwitch(
                'Arrives',
                _arrives,
                (value) => setState(() => _arrives = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _alertSwitch(
                'Leaves',
                _leaves,
                (value) => setState(() => _leaves = value),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Place alerts on')),
          value: _enabled,
          activeThumbColor: const Color(0xFFE98B72),
          onChanged: (value) => setState(() => _enabled = value),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE98B72),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(tr('Save place')),
          ),
        ),
      ],
    ),
  );

  Widget _alertSwitch(String label, bool value, ValueChanged<bool> onChanged) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Switch(
              value: value,
              activeThumbColor: const Color(0xFFE98B72),
              onChanged: onChanged,
            ),
          ],
        ),
      );
}
