import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/incident.dart';
import 'ai_service.dart';
import 'auth_service.dart';
import 'points_service.dart';
import 'risk_service.dart';

/// Review model
/// 1. Automatic: reports of the same type within 150 m and 2 hours merge into one incident.
/// 2. Crowd: nearby people vote "still there" / "gone"; reporters + "still there" votes verify it.
///    A volunteer's on-site "still there" verifies immediately; an AI-confirmed photo counts as one vote.
/// 3. Danger (live wire, open manhole) is urgent from the first report and verified at 2.
/// Lifecycle: reported -> verified -> acknowledged -> in_progress -> resolved -> closed
///            (a new report or 2 "still there" votes after "resolved" reopens it as verified).
class IncidentService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get incidents => _db.collection('incidents');
  static DocumentReference<Map<String, dynamic>> get statsRef => _db.collection('stats').doc('global');

  /// Photos live outside the incident so map and list listeners do not download them.
  static CollectionReference<Map<String, dynamic>> get photos => _db.collection('photos');

  static Future<String?> photoFor(Incident i) async {
    if (i.photo != null) return i.photo;
    if (!i.hasPhoto) return null;
    return (await photos.doc(i.id).get()).data()?['data'] as String?;
  }

  static Map<String, dynamic> _event(String status, {String? note}) => {
        'status': status,
        'by': AuthService.uid,
        'at': Timestamp.now(),
        if (note != null) 'note': note,
      };

  static bool _shouldVerify(IncidentType type, int reporters, int stillThere, int aiBoost) {
    final need = dangerTypes.contains(type) ? AppConfig.dangerVerifyThreshold : AppConfig.verifyThreshold;
    return reporters + stillThere + aiBoost >= need;
  }

  static String _deeper(String a, String b) => (depthRank[a] ?? 0) >= (depthRank[b] ?? 0) ? a : b;

  /// Incidents touched (report, vote or status change) in the last 3 days; closed ones filtered out.
  static Stream<List<Incident>> watchOpen() => incidents
      .where('updatedAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 3))))
      .snapshots()
      .map((s) => s.docs.map(Incident.fromDoc).where((i) => i.isOpen).toList());

  /// All incidents touched in the last [days] days, closed ones included (for AI reports).
  static Future<List<Incident>> recent(int days) async {
    final s = await incidents
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(Duration(days: days))))
        .get();
    return s.docs.map(Incident.fromDoc).toList();
  }

  /// Submit a report. Returns the incident id it was merged into or created.
  static Future<String> submitReport({
    required IncidentType type,
    required String depth,
    required LatLng at,
    String? note,
    String? photo,
    PhotoAnalysis? ai,
  }) async {
    final uid = AuthService.uid;
    final aiOk = ai != null && ai.trusted;
    // the merge lookup and the area lookup run together
    final (recent, area) = await (
      incidents
          .where('lastReportAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(AppConfig.mergeWindow)))
          .get(),
      RiskService.nearestArea(at),
    ).wait;
    var savePhoto = false;
    var newReporter = true; // repeat reports on the same spot earn no points
    const dist = Distance();
    Incident? match;
    for (final d in recent.docs) {
      final inc = Incident.fromDoc(d);
      // "other" reports are free text, so they never merge
      if (type != IncidentType.other &&
          inc.type == type &&
          inc.isOpen &&
          dist.as(LengthUnit.Meter, inc.point, at) <= AppConfig.mergeRadiusM) {
        match = inc;
        break;
      }
    }

    String incidentId;
    if (match == null) {
      final ref = incidents.doc();
      incidentId = ref.id;
      savePhoto = photo != null;
      await ref.set({
        'type': type.name,
        'lat': at.latitude,
        'lon': at.longitude,
        'area': area,
        'depth': type == IncidentType.water ? depth : 'none',
        if (note != null && note.isNotEmpty) 'note': note,
        'reporters': [uid],
        'stillThere': 0,
        'gone': 0,
        'voters': <String>[],
        'status': Status.reported,
        'urgent': dangerTypes.contains(type),
        'hasPhoto': photo != null,
        if (ai != null) 'ai': ai.toMap(),
        'aiBoost': aiOk ? 1 : 0,
        'createdAt': FieldValue.serverTimestamp(),
        'lastReportAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'history': [_event(Status.reported, note: aiOk ? 'photo confirmed by AI' : null)],
      });
    } else {
      incidentId = match.id;
      final ref = incidents.doc(match.id);
      await _db.runTransaction((tx) async {
        final inc = Incident.fromDoc(await tx.get(ref));
        final aiBoost = aiOk ? 1 : inc.aiBoost;
        savePhoto = !inc.hasPhoto && photo != null; // first photo of this spot
        final photoFields = {
          if (savePhoto) 'hasPhoto': true,
          if (inc.ai == null && ai != null) 'ai': ai.toMap(),
          if (aiBoost != inc.aiBoost) 'aiBoost': aiBoost,
        };
        newReporter = !inc.reporters.contains(uid);
        if (!newReporter) {
          tx.update(ref, {
            'lastReportAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            ...photoFields,
            if (inc.status == Status.resolved) ...{
              'status': Status.verified,
              'history': FieldValue.arrayUnion([_event(Status.verified, note: 'reopened: new report after resolution')]),
            },
          });
          return;
        }
        final reporters = [...inc.reporters, uid];
        var status = inc.status;
        Map<String, dynamic>? event;
        if (status == Status.resolved) {
          status = Status.verified;
          event = _event(Status.verified, note: 'reopened: new report after resolution');
        } else if (status == Status.reported && _shouldVerify(inc.type, reporters.length, inc.stillThere, aiBoost)) {
          status = Status.verified;
          event = _event(Status.verified);
        }
        tx.update(ref, {
          'reporters': reporters,
          'depth': type == IncidentType.water ? _deeper(inc.depth, depth) : 'none',
          'status': status,
          ...photoFields,
          'lastReportAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (event != null) 'history': FieldValue.arrayUnion([event]),
        });
      });
    }

    // photo, report log and points are independent: save them together
    await Future.wait([
      if (savePhoto)
        photos.doc(incidentId).set({'data': photo, 'uid': uid, 'createdAt': FieldValue.serverTimestamp()}),
      _db.collection('reports').add({
        'uid': uid,
        'type': type.name,
        'depth': depth,
        'lat': at.latitude,
        'lon': at.longitude,
        'incidentId': incidentId,
        'aiChecked': ai != null,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      if (newReporter) PointsService.add(Points.report + (aiOk ? Points.aiPhoto : 0), counter: 'n_report'),
    ]);
    return incidentId;
  }

  /// "Still there" (true) or "gone" (false). One vote per person per incident;
  /// after "resolved" a fresh round starts and reporters may vote too.
  static Future<void> vote(Incident i, {required bool stillThere, required String role}) async {
    final uid = AuthService.uid;
    final ref = incidents.doc(i.id);
    final counted = await _db.runTransaction<bool>((tx) async {
      final inc = Incident.fromDoc(await tx.get(ref));
      if (inc.voters.contains(uid) || (inc.reporters.contains(uid) && inc.status != Status.resolved)) return false;
      final yes = inc.stillThere + (stillThere ? 1 : 0);
      final no = inc.gone + (stillThere ? 0 : 1);
      var status = inc.status;
      String? note;

      if (stillThere) {
        if (status == Status.reported &&
            (role == Role.volunteer ||
                role == Role.admin ||
                _shouldVerify(inc.type, inc.reportCount, yes, inc.aiBoost))) {
          status = Status.verified;
          note = role == Role.volunteer ? 'verified on site by volunteer' : null;
        } else if (status == Status.resolved && yes >= 2) {
          status = Status.verified;
          note = 'reopened: people say the problem is still there';
        }
      } else {
        if (status == Status.resolved) {
          status = Status.closed;
          note = 'confirmed cleared';
        } else if ((status == Status.reported || status == Status.verified) && no >= AppConfig.closeOnGoneVotes) {
          status = Status.closed;
          note = 'gone, by crowd vote';
        }
      }

      tx.update(ref, {
        'voters': [...inc.voters, uid],
        'stillThere': yes,
        'gone': no,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status != inc.status) 'history': FieldValue.arrayUnion([_event(status, note: note)]),
      });
      return true;
    });
    if (counted) await PointsService.add(Points.vote, counter: 'n_vote');
  }

  /// Staff actions: acknowledge, start work, claim.
  static Future<void> setStatus(Incident i, String status, {bool claim = false}) => incidents.doc(i.id).update({
        'status': status,
        if (claim) 'assignedTo': AuthService.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([_event(status)]),
      });

  /// Resolve with cause and environmental impact; updates the city-wide impact counters.
  static Future<void> resolve(Incident i,
      {required String cause, required double plasticKg, required int inlets, String? note}) async {
    final batch = _db.batch();
    batch.update(incidents.doc(i.id), {
      'status': Status.resolved,
      // fresh confirmation round: earlier "still there" votes must not reopen it
      'voters': <String>[],
      'stillThere': 0,
      'gone': 0,
      'cause': cause,
      'plasticKg': plasticKg,
      'inletsCleared': inlets,
      'resolvedBy': AuthService.uid,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion([_event(Status.resolved, note: note)]),
    });
    batch.set(
        statsRef,
        {
          'resolved': FieldValue.increment(1),
          'plasticKg': FieldValue.increment(plasticKg),
          'inletsCleared': FieldValue.increment(inlets),
          'cause_$cause': FieldValue.increment(1),
        },
        SetOptions(merge: true));
    await batch.commit();
    await PointsService.add(Points.resolve, counter: 'n_resolve', plasticKg: plasticKg);
  }

  static Future<void> markForwarded(Incident i, String channel) => incidents.doc(i.id).update({
        'forwardedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([_event(i.status, note: 'forwarded via $channel')]),
      });

  // ---------------- forwarding to the ward council ----------------

  /// Contact for an area, configured by the admin in `contacts/{area}`: {name, email, phone}.
  static Future<Map<String, dynamic>?> contactFor(String area) async =>
      (await _db.collection('contacts').doc(area).get()).data();

  static String summaryBn(Incident i) {
    final what = i.type == IncidentType.water
        ? '${typeLabel[i.type]}${(depthLabel[i.depth] ?? '').isNotEmpty ? ' (${depthLabel[i.depth]} পানি)' : ''}'
        : '${i.isDanger ? '⚠️ ' : ''}${i.title}';
    return [
      'জলরেখা সতর্কবার্তা',
      'এলাকা: ${i.area}',
      'সমস্যা: $what',
      'রিপোর্ট করেছেন: ${i.reportCount} জন, নিশ্চিত করেছেন: ${i.stillThere} জন',
      if (i.aiBoost > 0) 'ছবি AI দিয়ে যাচাই করা হয়েছে',
      'প্রথম রিপোর্ট: ${timeAgo(i.createdAt)}',
      'অবস্থা: ${statusLabel[i.status]}',
      'ম্যাপ: https://maps.google.com/?q=${i.lat.toStringAsFixed(5)},${i.lon.toStringAsFixed(5)}',
      i.isDanger ? 'জীবনের ঝুঁকি আছে, অনুগ্রহ করে এখনই ব্যবস্থা নিন।' : 'অনুগ্রহ করে দ্রুত ব্যবস্থা নিন।',
    ].join('\n');
  }
}
