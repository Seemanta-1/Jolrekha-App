import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import 'auth_service.dart';
import 'incident_service.dart';
import 'location_service.dart';
import 'points_service.dart';
import 'risk_service.dart';

/// A clean-up drive created by a volunteer. Everyone nearby is invited; those who join form its team.
class CleanupEvent {
  final String id, title, description, area, createdBy, createdByName, status;
  final double lat, lon;
  final DateTime startAt;
  final List<String> members;
  final bool aiSuggested;
  final double plasticKg;
  final int inlets;

  CleanupEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.area,
    required this.createdBy,
    required this.createdByName,
    required this.status,
    required this.lat,
    required this.lon,
    required this.startAt,
    required this.members,
    required this.aiSuggested,
    required this.plasticKg,
    required this.inlets,
  });

  LatLng get point => LatLng(lat, lon);
  bool get isDone => status == 'done';
  bool isMember(String uid) => members.contains(uid);

  factory CleanupEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return CleanupEvent(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      area: (d['area'] as String?) ?? '',
      createdBy: (d['createdBy'] as String?) ?? '',
      createdByName: (d['createdByName'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'upcoming',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lon: (d['lon'] as num?)?.toDouble() ?? 0,
      startAt: (d['startAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      members: List<String>.from(d['members'] ?? const []),
      aiSuggested: d['aiSuggested'] == true,
      plasticKg: (d['plasticKg'] as num?)?.toDouble() ?? 0,
      inlets: (d['inlets'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessage {
  final String id, uid, name, text;
  final DateTime at;
  ChatMessage(this.id, this.uid, this.name, this.text, this.at);
}

class EventService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get events => _db.collection('events');

  /// Upcoming drives (and ones that started in the last 12 hours), soonest first.
  static Stream<List<CleanupEvent>> watchActive() =>
      events.where('status', isEqualTo: 'upcoming').snapshots().map((s) {
        final from = DateTime.now().subtract(const Duration(hours: 12));
        return s.docs.map(CleanupEvent.fromDoc).where((e) => e.startAt.isAfter(from)).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
      });

  /// Invitations: drives near me that I have not joined, dismissed or created.
  static List<CleanupEvent> invitationsFor(List<CleanupEvent> all, AppUser me) => all.where((e) {
        if (e.isMember(me.uid) || e.createdBy == me.uid || me.dismissedEvents.contains(e.id)) return false;
        final km = LocationService.kmTo(e.point);
        return km == null || km <= AppConfig.eventNotifyRadiusKm; // without GPS, show all
      }).toList();

  static Future<String> create({
    required AppUser me,
    required String title,
    required String description,
    required LatLng at,
    required DateTime startAt,
    bool aiSuggested = false,
  }) async {
    final ref = await events.add({
      'title': title,
      'description': description,
      'lat': at.latitude,
      'lon': at.longitude,
      'area': await RiskService.nearestArea(at),
      'startAt': Timestamp.fromDate(startAt),
      'createdBy': me.uid,
      'createdByName': me.name,
      'members': [me.uid],
      'status': 'upcoming',
      'aiSuggested': aiSuggested,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.collection('messages').add({
      'uid': me.uid,
      'name': me.name,
      'text': 'অভিযান তৈরি হলো। যারা যোগ দেবেন, এখানে কথা বলুন।',
      'at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> join(CleanupEvent e) async {
    if (e.isMember(AuthService.uid)) return;
    await events.doc(e.id).update({'members': FieldValue.arrayUnion([AuthService.uid])});
    await PointsService.add(Points.joinEvent, counter: 'n_event');
  }

  /// Organiser closes the drive with what was cleaned; adds it to the city-wide impact.
  static Future<void> complete(CleanupEvent e, {required double plasticKg, required int inlets}) async {
    final batch = _db.batch();
    batch.update(events.doc(e.id), {
      'status': 'done',
      'plasticKg': plasticKg,
      'inlets': inlets,
      'doneAt': FieldValue.serverTimestamp(),
    });
    batch.set(
        IncidentService.statsRef,
        {
          'cleanups': FieldValue.increment(1),
          'volunteers': FieldValue.increment(e.members.length),
          'plasticKg': FieldValue.increment(plasticKg),
          'inletsCleared': FieldValue.increment(inlets),
        },
        SetOptions(merge: true));
    await batch.commit();
    await PointsService.add(Points.organizeEvent, counter: 'n_organize', plasticKg: plasticKg);
  }

  // ---------------- team chat ----------------

  static Stream<List<ChatMessage>> messages(String eventId) => events
      .doc(eventId)
      .collection('messages')
      .orderBy('at')
      .limitToLast(300)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              ChatMessage(
                d.id,
                (d.data()['uid'] as String?) ?? '',
                (d.data()['name'] as String?) ?? '',
                (d.data()['text'] as String?) ?? '',
                (d.data()['at'] as Timestamp?)?.toDate() ?? DateTime.now(), // pending server time
              ),
          ]);

  static Future<void> send(String eventId, AppUser me, String text) =>
      events.doc(eventId).collection('messages').add({
        'uid': me.uid,
        'name': me.name,
        'text': text,
        'at': FieldValue.serverTimestamp(),
      });
}

/// "আজ 16:30", "আগামীকাল 09:00" or "14/10 10:00".
String whenBn(DateTime t) {
  final now = DateTime.now();
  final day = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (day == 0) return 'আজ $hm';
  if (day == 1) return 'আগামীকাল $hm';
  if (day == -1) return 'গতকাল $hm';
  return '${t.day}/${t.month} $hm';
}
