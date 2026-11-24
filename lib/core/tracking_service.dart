import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'db.dart';

/// Driver phone: sends GPS position to the shipment (and the public tracking doc) while a trip is active.
class TrackingService {
  static StreamSubscription<Position>? _sub;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static String? active;

  /// Returns an error message, or null when tracking started.
  static Future<String?> start(String id) async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'Please turn ON location (GPS) on this phone.';
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return 'Location permission is needed. Allow it in the phone settings for this app.';
    }
    await stop();
    active = id;
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'B.R. Edible Oils',
              notificationText: 'Sharing shipment location',
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (DateTime.now().difference(_last).inSeconds < 20) return;
      _push(id, pos);
    });
    try {
      _push(id, await Geolocator.getCurrentPosition());
    } catch (_) {}
    return null;
  }

  static void _push(String id, Position p) {
    _last = DateTime.now();
    final data = {
      'lastLat': p.latitude,
      'lastLng': p.longitude,
      'lastAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final b = Db.fs.batch();
    b.update(Db.c('shipments').doc(id), data);
    b.update(Db.c('tracking').doc(id), data);
    Db.commit(b);
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    active = null;
  }
}
