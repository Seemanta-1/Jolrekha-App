import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/incident.dart';

class Place {
  final String area;
  final LatLng point;
  final double pPlace; // P(this place waterlogs | Dhaka waterlogs), from the news dataset
  Place(this.area, this.point, this.pPlace);
}

class PlaceRisk {
  final Place place;
  final double risk;
  final String level; // low | medium | high
  final int drainReports; // open "drain blocked" reports within 1 km
  final int waterNow; // open waterlogging reports within 1 km
  PlaceRisk(this.place, this.risk, this.level, {this.drainReports = 0, this.waterNow = 0});

  /// Why the AI model rates this place as it does, in Bangla.
  String get why => [
        if (drainReports > 0) '$drainReportsটি ড্রেন বন্ধের রিপোর্ট',
        if (waterNow > 0) 'এখন $waterNowটি জায়গায় পানি',
      ].join(', ');
}

class DayRisk {
  final String date; // yyyy-mm-dd
  final double rainMm;
  final double pCity;
  DayRisk(this.date, this.rainMm, this.pCity);
}

/// Runs the model trained in Colab (assets/model.json) on the Open-Meteo forecast.
class RiskService {
  static Map<String, dynamic>? _model;
  static List<Place>? _places;

  static Future<Map<String, dynamic>> model() async =>
      _model ??= jsonDecode(await rootBundle.loadString('assets/model.json')) as Map<String, dynamic>;

  static Future<List<Place>> places() async {
    if (_places != null) return _places!;
    final m = await model();
    _places = (m['places'] as List)
        .map((p) => Place(
              p['area'] as String,
              LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
              (p['p_place'] as num).toDouble(),
            ))
        .toList();
    return _places!;
  }

  static List<double> _nums(dynamic l) => (l as List).map((e) => (e as num).toDouble()).toList();

  /// Logistic model: log1p features -> standardise -> linear -> sigmoid.
  static double pCity(Map<String, dynamic> m, Map<String, double> f) {
    final feats = List<String>.from(m['features'] as List);
    final mean = _nums(m['scaler_mean']), scale = _nums(m['scaler_scale']), coef = _nums(m['coef']);
    var z = (m['intercept'] as num).toDouble();
    for (var i = 0; i < feats.length; i++) {
      final x = log(1 + (f[feats[i]] ?? 0));
      z += coef[i] * ((x - mean[i]) / scale[i]);
    }
    return 1 / (1 + exp(-z));
  }

  /// Returns [today, tomorrow].
  static Future<List<DayRisk>> forecast() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${AppConfig.dhakaLat}',
      'longitude': '${AppConfig.dhakaLon}',
      'hourly': 'precipitation',
      'past_days': '2',
      'forecast_days': '2',
      'timezone': 'Asia/Dhaka',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Forecast unavailable (${res.statusCode})');
    final hourly = (jsonDecode(res.body) as Map<String, dynamic>)['hourly'] as Map<String, dynamic>;
    final times = List<String>.from(hourly['time'] as List);
    final rain = (hourly['precipitation'] as List).map((e) => (e as num?)?.toDouble() ?? 0.0).toList();

    final byDay = <String, List<double>>{};
    for (var i = 0; i < times.length; i++) {
      byDay.putIfAbsent(times[i].substring(0, 10), () => []).add(rain[i]);
    }
    final days = byDay.keys.toList()..sort(); // day-2, day-1, today, tomorrow
    final sum = days.map((d) => byDay[d]!.fold<double>(0, (a, b) => a + b)).toList();
    final mx = days.map((d) => byDay[d]!.fold<double>(0, (a, b) => max(a, b))).toList();

    final m = await model();
    final out = <DayRisk>[];
    for (var i = 2; i < days.length; i++) {
      out.add(DayRisk(days[i], sum[i], pCity(m, {
        'rain_d': sum[i],
        'rain_prev': sum[i - 1],
        'rain_3d': sum[i] + sum[i - 1] + sum[i - 2],
        'max_1h_2d': max(mx[i], mx[i - 1]),
      })));
    }
    return out;
  }

  // Thresholds from model.json (risk_levels); set when placeRisks() loads the model.
  static double _high = 0.25, _medium = 0.10;

  /// low | medium | high for a place risk, using the trained model's thresholds.
  static String levelOf(double risk) => risk >= _high ? 'high' : risk >= _medium ? 'medium' : 'low';

  /// Smart risk: the trained model (forecast rain x place history) adjusted with live crowd reports.
  /// Each open "drain blocked" report within 1 km raises the risk by half (blocked inlets flood first),
  /// and reported water within 1 km makes the place at least medium (it is already wet).
  static Future<List<PlaceRisk>> placeRisks(double pCity, {List<Incident> crowd = const []}) async {
    final m = await model();
    final lv = (m['risk_levels'] as Map<String, dynamic>?) ?? {'high': 0.25, 'medium': 0.10};
    final hi = (lv['high'] as num).toDouble(), mid = (lv['medium'] as num).toDouble();
    _high = hi;
    _medium = mid;
    const d = Distance();
    final list = (await places()).map((p) {
      var drain = 0, water = 0;
      for (final i in crowd) {
        if (i.status == Status.resolved || d.as(LengthUnit.Meter, p.point, i.point) > 1000) continue;
        if (i.type == IncidentType.garbage) drain += min(i.weight, 3);
        if (i.type == IncidentType.water) water++;
      }
      var r = min(0.95, pCity * p.pPlace * (1 + 0.5 * drain));
      if (water > 0) r = max(r, mid);
      return PlaceRisk(p, r, levelOf(r), drainReports: drain, waterNow: water);
    }).toList()
      ..sort((a, b) => b.risk.compareTo(a.risk));
    return list;
  }

  static Future<String> nearestArea(LatLng at) async {
    const d = Distance();
    final ps = List<Place>.of(await places());
    ps.sort((a, b) => d.as(LengthUnit.Meter, a.point, at).compareTo(d.as(LengthUnit.Meter, b.point, at)));
    return ps.first.area;
  }
}
