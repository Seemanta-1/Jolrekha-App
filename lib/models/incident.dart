import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum IncidentType { water, wire, manhole, garbage, pothole, tree, streetlight, other }

/// Danger types are urgent from the first report and go straight to the ward council.
const dangerTypes = {IncidentType.wire, IncidentType.manhole};

/// Problems a volunteer team can fix themselves (clear drain inlets, pick up waste).
const volunteerFixable = {IncidentType.water, IncidentType.garbage};

class Status {
  static const reported = 'reported';
  static const verified = 'verified';
  static const acknowledged = 'acknowledged';
  static const inProgress = 'in_progress';
  static const resolved = 'resolved';
  static const closed = 'closed';
}

const statusLabel = {
  Status.reported: 'রিপোর্ট হয়েছে',
  Status.verified: 'যাচাইকৃত',
  Status.acknowledged: 'কর্তৃপক্ষ দেখেছে',
  Status.inProgress: 'কাজ চলছে',
  Status.resolved: 'সমাধান হয়েছে',
  Status.closed: 'বন্ধ',
};

const typeLabel = {
  IncidentType.water: 'জলাবদ্ধতা',
  IncidentType.wire: 'পানিতে বিদ্যুতের তার',
  IncidentType.manhole: 'খোলা ম্যানহোল',
  IncidentType.garbage: 'ড্রেন বন্ধ / ময়লা',
  IncidentType.pothole: 'ভাঙা রাস্তা / গর্ত',
  IncidentType.tree: 'গাছ পড়েছে',
  IncidentType.streetlight: 'স্ট্রিট লাইট নষ্ট',
  IncidentType.other: 'অন্যান্য',
};

const typeIcon = {
  IncidentType.water: Icons.water_drop,
  IncidentType.wire: Icons.bolt,
  IncidentType.manhole: Icons.warning_rounded,
  IncidentType.garbage: Icons.delete_outline,
  IncidentType.pothole: Icons.add_road,
  IncidentType.tree: Icons.park_outlined,
  IncidentType.streetlight: Icons.lightbulb_outline,
  IncidentType.other: Icons.report_outlined,
};

const depthLabel = {
  'ankle': 'গোড়ালি',
  'knee': 'হাঁটু',
  'waist': 'কোমর',
  'chest': 'বুক বা বেশি',
  'none': '',
};

const depthRank = {'none': 0, 'ankle': 1, 'knee': 2, 'waist': 3, 'chest': 4};

/// What can still get through water of this depth on a Dhaka street.
const passLabel = {
  'ankle': 'সব যানবাহন চলবে',
  'knee': 'হেঁটে ও রিকশায় যাওয়া যাবে, বাইক-CNG-কার না',
  'waist': 'শুধু বাস/ট্রাক যাবে',
  'chest': 'চলাচল বন্ধ',
};

enum Vehicle { walk, rickshaw, car, bus }

const vehicleLabel = {
  Vehicle.walk: 'হেঁটে',
  Vehicle.rickshaw: 'রিকশা',
  Vehicle.car: 'বাইক/CNG/কার',
  Vehicle.bus: 'বাস',
};

const vehicleIcon = {
  Vehicle.walk: Icons.directions_walk,
  Vehicle.rickshaw: Icons.pedal_bike,
  Vehicle.car: Icons.directions_car,
  Vehicle.bus: Icons.directions_bus,
};

/// Deepest water (depthRank) each vehicle can cross; keep in line with passLabel.
const vehicleMaxDepth = {Vehicle.walk: 2, Vehicle.rickshaw: 2, Vehicle.car: 1, Vehicle.bus: 3};

/// OpenRouteService profile for each vehicle.
const vehicleProfile = {
  Vehicle.walk: 'foot-walking',
  Vehicle.rickshaw: 'cycling-regular',
  Vehicle.car: 'driving-car',
  Vehicle.bus: 'driving-hgv',
};

const causeLabel = {
  'plastic': 'প্লাস্টিক/পলিথিনে ড্রেন বন্ধ',
  'construction': 'নির্মাণের মাটি-বালু',
  'broken_drain': 'ভাঙা ড্রেন',
  'canal': 'খাল দখল বা ভরাট',
  'no_drain': 'ড্রেন নেই',
  'other': 'অন্যান্য',
};

class Incident {
  final String id;
  final IncidentType type;
  final double lat, lon;
  final String area;
  final String depth;
  final List<String> reporters;
  final int stillThere, gone;
  final List<String> voters;
  final String status;
  final bool urgent;
  final DateTime? createdAt, lastReportAt, forwardedAt;
  final String? assignedTo, cause, note;
  final double plasticKg;
  final String? photo; // legacy: photo stored on the incident itself
  final bool hasPhoto; // the photo lives in photos/{id} and loads on demand
  final Map<String, dynamic>? ai; // result of the AI photo check
  final int aiBoost; // 1 when the AI confirmed the photo

  Incident({
    required this.id,
    required this.type,
    required this.lat,
    required this.lon,
    required this.area,
    required this.depth,
    required this.reporters,
    required this.stillThere,
    required this.gone,
    required this.voters,
    required this.status,
    required this.urgent,
    this.createdAt,
    this.lastReportAt,
    this.forwardedAt,
    this.assignedTo,
    this.cause,
    this.note,
    this.plasticKg = 0,
    this.photo,
    this.hasPhoto = false,
    this.ai,
    this.aiBoost = 0,
  });

  LatLng get point => LatLng(lat, lon);
  bool get isDanger => dangerTypes.contains(type);
  bool get isOpen => status != Status.closed;
  bool get isVerified => status != Status.reported;
  int get reportCount => reporters.length;

  /// How many people back this spot: used for the heat colouring on the map.
  int get weight => reportCount + stillThere + aiBoost;

  /// Water with a known depth; other problems have no passability class.
  bool get hasDepth => type == IncidentType.water && (depthRank[depth] ?? 0) > 0;

  /// Whether this vehicle can get past. Unknown depth counts as blocked, to be safe.
  bool passableBy(Vehicle v) => hasDepth && depthRank[depth]! <= vehicleMaxDepth[v]!;

  String get title => type == IncidentType.other && (note ?? '').isNotEmpty ? note! : typeLabel[type]!;

  factory Incident.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    DateTime? ts(String k) => d[k] is Timestamp ? (d[k] as Timestamp).toDate() : null;
    return Incident(
      id: doc.id,
      type: IncidentType.values.firstWhere((t) => t.name == d['type'], orElse: () => IncidentType.other),
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lon: (d['lon'] as num?)?.toDouble() ?? 0,
      area: (d['area'] as String?) ?? '',
      depth: (d['depth'] as String?) ?? 'none',
      reporters: List<String>.from(d['reporters'] ?? const []),
      stillThere: (d['stillThere'] as num?)?.toInt() ?? 0,
      gone: (d['gone'] as num?)?.toInt() ?? 0,
      voters: List<String>.from(d['voters'] ?? const []),
      status: (d['status'] as String?) ?? Status.reported,
      urgent: d['urgent'] == true,
      createdAt: ts('createdAt') ?? (d.containsKey('createdAt') ? DateTime.now() : null),
      lastReportAt: ts('lastReportAt'),
      forwardedAt: ts('forwardedAt'),
      assignedTo: d['assignedTo'] as String?,
      cause: d['cause'] as String?,
      note: d['note'] as String?,
      plasticKg: (d['plasticKg'] as num?)?.toDouble() ?? 0,
      photo: d['photo'] as String?,
      hasPhoto: d['hasPhoto'] == true || d['photo'] != null,
      ai: (d['ai'] as Map?)?.cast<String, dynamic>(),
      aiBoost: (d['aiBoost'] as num?)?.toInt() ?? 0,
    );
  }
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'এইমাত্র';
  if (m < 60) return '$m মিনিট আগে';
  final h = m ~/ 60;
  if (h < 24) return '$h ঘণ্টা আগে';
  return '${h ~/ 24} দিন আগে';
}
