import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';

class RouteResult {
  final List<LatLng> points;
  final double km;
  final double minutes;
  final int avoided;
  RouteResult(this.points, this.km, this.minutes, this.avoided);
}

/// Water-free route: every flooded spot becomes a small square that the route must avoid.
class RouteService {
  static const _d = Distance();

  static List<List<double>> _square(LatLng c, double halfSideM) {
    final n = _d.offset(c, halfSideM, 0), s = _d.offset(c, halfSideM, 180);
    final e = _d.offset(c, halfSideM, 90), w = _d.offset(c, halfSideM, 270);
    final ring = [
      [w.longitude, n.latitude],
      [e.longitude, n.latitude],
      [e.longitude, s.latitude],
      [w.longitude, s.latitude],
      [w.longitude, n.latitude],
    ];
    return ring.map((p) => [p[0], p[1]]).toList();
  }

  static Future<RouteResult> route(LatLng from, LatLng to, List<LatLng> avoid, {String profile = 'driving-car'}) async {
    // never block the start or the destination itself
    final blocks = avoid
        .where((p) => _d.as(LengthUnit.Meter, p, from) > 200 && _d.as(LengthUnit.Meter, p, to) > 200)
        .toList();
    final body = <String, dynamic>{
      'coordinates': [
        [from.longitude, from.latitude],
        [to.longitude, to.latitude],
      ],
      if (blocks.isNotEmpty)
        'options': {
          'avoid_polygons': {
            'type': 'MultiPolygon',
            'coordinates': blocks.map((p) => [_square(p, 120)]).toList(),
          }
        },
    };
    final res = await http.post(
      Uri.parse('https://api.openrouteservice.org/v2/directions/$profile/geojson'),
      headers: {'Authorization': AppConfig.orsApiKey, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Route failed (${res.statusCode}): ${res.body.length > 160 ? res.body.substring(0, 160) : res.body}');
    }
    final feature = (jsonDecode(res.body)['features'] as List).first as Map<String, dynamic>;
    final coords = (feature['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    final summary = feature['properties']['summary'] as Map<String, dynamic>? ?? {};
    return RouteResult(
      coords,
      ((summary['distance'] as num?) ?? 0) / 1000,
      ((summary['duration'] as num?) ?? 0) / 60,
      blocks.length,
    );
  }
}
