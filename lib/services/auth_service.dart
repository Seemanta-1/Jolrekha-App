import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config.dart';

/// Roles: citizen (default), volunteer, authority (ward council), admin.
class Role {
  static const citizen = 'citizen';
  static const volunteer = 'volunteer';
  static const authority = 'authority';
  static const admin = 'admin';
  static const label = {
    citizen: 'নাগরিক',
    volunteer: 'স্বেচ্ছাসেবক',
    authority: 'ওয়ার্ড কাউন্সিল',
    admin: 'অ্যাডমিন',
  };
}

/// Account approval for volunteers and ward councils.
class Approval {
  static const approved = 'approved';
  static const pending = 'pending';
  static const rejected = 'rejected';
  static const suspended = 'suspended';
}

class AppUser {
  final String uid;
  final String name;
  final String role;
  final String? requestedRole; // what a volunteer / council registered as, until the admin approves
  final String status;
  final List<String> areas; // areas a ward council is responsible for (empty = all)
  final String phone, email, org;
  final bool emailVerified;
  final List<String> dismissedEvents;

  AppUser({
    required this.uid,
    required this.name,
    required this.role,
    required this.requestedRole,
    required this.status,
    required this.areas,
    required this.phone,
    required this.email,
    required this.org,
    required this.emailVerified,
    required this.dismissedEvents,
  });

  bool get isStaff => role == Role.volunteer || role == Role.authority || role == Role.admin;
  bool get isAuthority => role == Role.authority || role == Role.admin;
  bool get isVolunteer => role == Role.volunteer || role == Role.admin;
  bool get isAdmin => role == Role.admin;
  bool get isPending => status == Approval.pending;

  bool covers(String area) => areas.isEmpty || areas.contains(area);

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? <String, dynamic>{};
    return AppUser(
      uid: s.id,
      name: (d['name'] as String?) ?? 'নাগরিক',
      role: (d['role'] as String?) ?? Role.citizen,
      requestedRole: d['requestedRole'] as String?,
      status: (d['status'] as String?) ?? Approval.approved,
      areas: List<String>.from(d['areas'] ?? const []),
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      org: (d['org'] as String?) ?? '',
      emailVerified: d['emailVerified'] == true,
      dismissedEvents: List<String>.from(d['dismissedEvents'] ?? const []),
    );
  }
}

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get current => _auth.currentUser;
  static String get uid => _auth.currentUser!.uid;
  static DocumentReference<Map<String, dynamic>> _userRef(String id) => _db.collection('users').doc(id);
  static DocumentReference<Map<String, dynamic>> _boardRef(String id) => _db.collection('leaderboard').doc(id);

  static Stream<User?> authChanges() => _auth.authStateChanges();

  /// Bangladeshi mobile number as 01XXXXXXXXX, or null if it is not one.
  static String? normalizePhone(String input) {
    var d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('880')) d = d.substring(2);
    return RegExp(r'^01[3-9]\d{8}$').hasMatch(d) ? d : null;
  }

  /// Citizens: phone number only, no OTP. The number maps to an internal email account,
  /// so the same number logs into the same account (and points) on any device.
  static Future<void> phoneLogin({required String name, required String phone}) async {
    final p = normalizePhone(phone)!;
    final email = '88$p@${AppConfig.phoneEmailDomain}';
    final password = 'jr-$p-citizen';
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    }
    final ref = _userRef(uid);
    if (!(await ref.get()).exists) {
      await ref.set({
        'name': name,
        'phone': p,
        'role': Role.citizen,
        'status': Approval.approved,
        'areas': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _boardRef(uid).set({'name': name, 'role': Role.citizen, 'points': 0}, SetOptions(merge: true));
    }
  }

  /// Volunteers and ward councils: email + password.
  static Future<void> staffLogin({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// Registers a volunteer or ward council. The account stays pending until the email
  /// is verified and an admin approves it.
  static Future<void> registerStaff({
    required String role,
    required String name,
    required String phone,
    required String email,
    required String password,
    required String org,
    required List<String> areas,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user!.sendEmailVerification();
    await _userRef(cred.user!.uid).set({
      'name': name,
      'phone': phone,
      'email': email.trim(),
      'org': org,
      'role': Role.citizen, // only the admin can raise it
      'requestedRole': role,
      'status': Approval.pending,
      'areas': areas,
      'emailVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _boardRef(cred.user!.uid).set({'name': name, 'role': Role.citizen, 'points': 0}, SetOptions(merge: true));
  }

  static Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  static Future<void> resendVerification() => _auth.currentUser!.sendEmailVerification();

  /// Reloads the auth user; records a verified email so the admin can see it.
  static Future<bool> checkEmailVerified() async {
    await _auth.currentUser!.reload();
    final ok = _auth.currentUser!.emailVerified;
    if (ok) await _userRef(uid).update({'emailVerified': true});
    return ok;
  }

  static Future<void> signOut() => _auth.signOut();

  /// The signed-in user's profile; null while the document does not exist yet.
  static Stream<AppUser?> watchUser(String id) =>
      _userRef(id).snapshots().map((s) => s.exists ? AppUser.fromDoc(s) : null);

  static Future<void> updateName(String name) async {
    await _userRef(uid).update({'name': name});
    await _boardRef(uid).set({'name': name}, SetOptions(merge: true));
  }

  static Future<void> dismissEvent(String eventId) =>
      _userRef(uid).update({'dismissedEvents': FieldValue.arrayUnion([eventId])});

  // ---------------- admin ----------------

  static Stream<List<AppUser>> watchPending() => _db
      .collection('users')
      .where('status', isEqualTo: Approval.pending)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  static Future<void> approve(AppUser u) async {
    final role = u.requestedRole ?? Role.volunteer;
    await _userRef(u.uid).update({'role': role, 'status': Approval.approved, 'approvedBy': uid});
    await _boardRef(u.uid).set({'role': role}, SetOptions(merge: true));
  }

  static Future<void> reject(AppUser u) =>
      _userRef(u.uid).update({'status': Approval.rejected, 'approvedBy': uid});

  /// Everyone, newest first (admin website).
  static Stream<List<AppUser>> watchAllUsers() => _db
      .collection('users')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  static Future<void> setRole(AppUser u, String role) async {
    await _userRef(u.uid).update({'role': role, 'status': Approval.approved, 'approvedBy': uid});
    await _boardRef(u.uid).set({'role': role}, SetOptions(merge: true));
  }

  static Future<void> setAreas(AppUser u, List<String> areas) => _userRef(u.uid).update({'areas': areas});

  /// Suspended users see a message instead of the app; restoring puts them back as approved.
  static Future<void> setSuspended(AppUser u, bool suspended) => _userRef(u.uid)
      .update({'status': suspended ? Approval.suspended : Approval.approved, 'approvedBy': uid});
}

/// Firebase auth errors in Bangla.
String authErrorBn(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'ইমেইল ঠিক নেই';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'ইমেইল বা পাসওয়ার্ড ভুল';
      case 'email-already-in-use':
        return 'এই ইমেইলে আগেই অ্যাকাউন্ট আছে, লগইন করুন';
      case 'weak-password':
        return 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে';
      case 'too-many-requests':
        return 'অনেকবার চেষ্টা হয়েছে, একটু পরে আবার চেষ্টা করুন';
      case 'network-request-failed':
        return 'ইন্টারনেট সংযোগ দেখুন';
      case 'operation-not-allowed':
        return 'Firebase console এ Email/Password লগইন চালু করা নেই';
    }
    return e.message ?? e.code;
  }
  return '$e';
}
