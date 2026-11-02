import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/cloud_couple_store.dart';

/// Sends a privacy-minimized summary to the Android home-screen widget.
/// Coordinates and account credentials are never written to widget storage.
class AndroidWidgetSync {
  AndroidWidgetSync._();

  static const _channel = MethodChannel('com.jcm.closer/widget');

  static Future<bool> requestLocationNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('requestLocationNotification') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> sync(CloudCoupleStore store) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    // The widget is for a signed-in couple, not temporary Couple Court rooms.
    if (store.user == null || store.roomSession != null || store.courtOnly) {
      await _write({'paired': false});
      return;
    }

    final partnerUid = store.partnerUid;
    if (!store.paired || partnerUid == null) {
      await _write({'paired': false});
      return;
    }

    final locations = store.locations;
    final mine = _point(locations[store.uid]);
    final partner = _point(locations[partnerUid]);
    if (mine == null || partner == null) {
      await _write({
        'paired': true,
        'name': store.yourName,
        'partner': store.partnerName,
        'locationShared': false,
      });
      return;
    }

    final lastUpdated = [
      mine.$3,
      partner.$3,
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    await _write({
      'paired': true,
      'name': store.yourName,
      'partner': store.partnerName,
      'locationShared': true,
      'distanceMeters': _distanceMeters(mine, partner),
      'updatedAt': lastUpdated.millisecondsSinceEpoch,
    });
  }

  static Future<void> clearDistance() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _write({'paired': true, 'clearLocation': true});
  }

  static Future<void> _write(Map<String, Object?> data) async {
    try {
      await _channel.invokeMethod<void>('syncWidget', data);
    } on MissingPluginException {
      // Allows the Flutter app to continue if this is an older installed build.
    } on PlatformException {
      // A widget refresh should never interrupt the main app flow.
    }
  }

  static (double, double, DateTime)? _point(dynamic value) {
    if (value is! Map || value['lat'] is! num || value['lon'] is! num) {
      return null;
    }
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (updatedAt == null) return null;
    return (
      (value['lat'] as num).toDouble(),
      (value['lon'] as num).toDouble(),
      updatedAt.toLocal(),
    );
  }

  static double _distanceMeters(
    (double, double, DateTime) a,
    (double, double, DateTime) b,
  ) {
    const earthRadius = 6371000.0;
    final lat1 = a.$1 * math.pi / 180;
    final lat2 = b.$1 * math.pi / 180;
    final dLat = (b.$1 - a.$1) * math.pi / 180;
    final dLon = (b.$2 - a.$2) * math.pi / 180;
    final haversine =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return earthRadius *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}
