import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// The phone's position, shared by the map, danger alerts and nearby event invitations.
/// It stays on the device: nothing is uploaded.
class LocationService {
  static final position = ValueNotifier<LatLng?>(null);
  static StreamSubscription<Position>? _sub;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      position.value = LatLng(pos.latitude, pos.longitude);
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 40),
      ).listen((pos) => position.value = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // no location: the app still works, only distance-based features are off
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    position.value = null;
  }

  /// Kilometres from the user to [p], or null without a location.
  static double? kmTo(LatLng p) {
    final me = position.value;
    if (me == null) return null;
    return const Distance().as(LengthUnit.Meter, me, p) / 1000;
  }
}
