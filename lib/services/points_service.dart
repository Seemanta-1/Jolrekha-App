import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/incident.dart';
import 'auth_service.dart';

class LeaderRow {
  final String uid, name, role;
  final int points;
  LeaderRow(this.uid, this.name, this.role, this.points);
}

/// One player's points and activity counters, for levels and achievements.
class PlayerStats {
  final int total, month, reports, verified, votes, resolved, events, organized;
  final double plasticKg;
  PlayerStats(Map<String, dynamic> d)
      : total = _n(d['points']),
        month = _n(d[PointsService.monthKey()]),
        reports = _n(d['n_report']),
        verified = _n(d['n_verified']),
        votes = _n(d['n_vote']),
        resolved = _n(d['n_resolve']),
        events = _n(d['n_event']),
        organized = _n(d['n_organize']),
        plasticKg = (d['plasticKg'] as num?)?.toDouble() ?? 0;

  static int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  /// Share of reports the crowd verified; null until there is a report.
  double? get accuracy => reports == 0 ? null : (verified / reports).clamp(0, 1).toDouble();

  bool get isAccurate =>
      reports >= Points.accurateMinReports && (accuracy ?? 0) >= Points.accurateRate;
}

/// Reward points for the leaderboard: `leaderboard/{uid}` holds the public name, total and monthly points
/// and activity counters (phone numbers and emails stay private in `users`).
class PointsService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _board => _db.collection('leaderboard');

  /// Field for this month's points, e.g. m202610.
  static String monthKey([DateTime? t]) {
    final d = t ?? DateTime.now();
    return 'm${d.year}${d.month.toString().padLeft(2, '0')}';
  }

  /// [counter] is the activity to count (n_report, n_vote, n_resolve, n_event, n_organize).
  static Future<void> add(int points, {String? counter, double plasticKg = 0}) => _board.doc(AuthService.uid).set({
        'points': FieldValue.increment(points),
        monthKey(): FieldValue.increment(points),
        if (counter != null) counter: FieldValue.increment(1),
        if (plasticKg > 0) 'plasticKg': FieldValue.increment(plasticKg),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Pays the bonus for my reports the crowd has verified since the last check.
  /// Runs on my own device because only I can write my leaderboard row. Returns (reports, points) paid.
  static Future<(int, int)> claimVerified() async {
    final uid = AuthService.uid;
    final mine = await _db.collection('incidents').where('reporters', arrayContains: uid).get();
    final ok = [
      for (final d in mine.docs)
        if (((d.data()['history'] as List?) ?? const [])
            .any((e) => e is Map && e['status'] != Status.reported && e['status'] != Status.closed))
          d.id,
    ];
    if (ok.isEmpty) return (0, 0);
    final ref = _board.doc(uid);
    return _db.runTransaction<(int, int)>((tx) async {
      final d = (await tx.get(ref)).data() ?? {};
      final claimed = Set<String>.from(d['verifiedIds'] ?? const []);
      final fresh = ok.where((id) => !claimed.contains(id)).toList();
      if (fresh.isEmpty) return (0, 0);
      final each = PlayerStats(d).isAccurate ? Points.accurateVerified : Points.verified;
      final pts = each * fresh.length;
      tx.set(
          ref,
          {
            'points': FieldValue.increment(pts),
            monthKey(): FieldValue.increment(pts),
            'n_verified': FieldValue.increment(fresh.length),
            'verifiedIds': FieldValue.arrayUnion(fresh),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return (fresh.length, pts);
    });
  }

  static Stream<List<LeaderRow>> top({bool monthly = true, int limit = 20}) {
    final field = monthly ? monthKey() : 'points';
    return _board.orderBy(field, descending: true).limit(limit).snapshots().map((s) => [
          for (final d in s.docs)
            LeaderRow(
              d.id,
              (d.data()['name'] as String?) ?? 'নাগরিক',
              (d.data()['role'] as String?) ?? Role.citizen,
              (d.data()[field] as num?)?.toInt() ?? 0,
            ),
        ]);
  }

  static Stream<PlayerStats> mine(String uid) => _board.doc(uid).snapshots().map((s) => PlayerStats(s.data() ?? {}));
}
