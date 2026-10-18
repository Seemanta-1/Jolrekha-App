/// Central settings. Change these, not the code.
class AppConfig {
  // Map centre (central Dhaka)
  static const double dhakaLat = 23.76;
  static const double dhakaLon = 90.39;

  // OpenRouteService key for water-free routing, read from env.json at build time
  // (flutter run --dart-define-from-file=env.json). Free key: https://openrouteservice.org/dev/#/signup
  static const String orsApiKey = String.fromEnvironment('ORS_API_KEY');

  // AI: Firebase AI Logic with the Gemini Developer API (free on the Spark plan).
  // Enable it in Firebase console → AI Logic → Get started → Gemini Developer API.
  static const String aiModel = 'gemini-3.5-flash';
  static const double aiMinConfidence = 0.7; // an AI-checked photo counts as one extra confirmation

  // Review model
  static const double mergeRadiusM = 150; // reports this close become one incident
  static const Duration mergeWindow = Duration(hours: 2);
  static const int verifyThreshold = 3; // reporters + "still there" votes needed (non-danger)
  static const int dangerVerifyThreshold = 2; // live wire / open manhole
  static const int closeOnGoneVotes = 3; // "gone" votes that close an unresolved incident

  // Safety alert
  static const double dangerAlertRadiusM = 200;

  // Clean-up events: people within this distance get the in-app invitation
  static const double eventNotifyRadiusKm = 5;

  // Citizens log in with a phone number only (no OTP): each number maps to an internal account.
  static const String phoneEmailDomain = 'phone.jolrekha.app';
}

/// Reward points for the leaderboard.
class Points {
  static const report = 5;
  static const aiPhoto = 5; // extra when the report has a photo the AI confirmed
  static const vote = 2;
  static const joinEvent = 10;
  static const organizeEvent = 30;
  static const resolve = 20;

  // Accuracy: a report earns its bonus only once the crowd verifies it.
  static const verified = 10;
  static const accurateVerified = 15; // when accuracy is high (below)
  static const accurateRate = 0.8;
  static const accurateMinReports = 5;

  /// Monthly prizes for the top three.
  static const prizes = [
    'স্বর্ণ পদক + "পরিবেশ বীর" সনদ',
    'রৌপ্য পদক + সনদ',
    'ব্রোঞ্জ পদক + সনদ',
  ];

  /// Levels by total points, lowest first.
  static const levels = [
    (0, 'নতুন সদস্য'),
    (50, 'সক্রিয় নাগরিক'),
    (200, 'জলযোদ্ধা'),
    (500, 'পরিবেশ বীর'),
    (1000, 'ওয়ার্ড হিরো'),
  ];

  static String badge(int points) => levels.lastWhere((l) => points >= l.$1).$2;

  /// The next level and the points it needs, or null at the top.
  static (int, String)? nextLevel(int points) {
    for (final l in levels) {
      if (l.$1 > points) return l;
    }
    return null;
  }
}
