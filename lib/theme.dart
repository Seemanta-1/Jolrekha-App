import 'package:flutter/material.dart';

/// Colours follow a flood gauge: calm water to danger.
class JR {
  static const ink = Color(0xFF0F2A3D); // deep monsoon blue: text and brand
  static const water = Color(0xFF1F6F9F); // brand water blue
  static const surface = Color(0xFFF3F7F9); // cool grey-blue background
  static const low = Color(0xFF3FA796); // safe teal
  static const medium = Color(0xFFE0A100); // monsoon amber
  static const high = Color(0xFFD7263D); // flood red
  static const danger = Color(0xFF8E1B5B); // live wire / manhole
  static const done = Color(0xFF4C8C2B); // resolved

  // Map: AI flood-risk zones are blue (water), crowd reports are yellow -> red (heat).
  static const riskHigh = Color(0xFF0D47A1); // AI: high risk (dark blue)
  static const riskMedium = Color(0xFF42A5F5); // AI: medium risk (light blue)
  static const heat1 = Color(0xFFF9A825); // 1 person (yellow)
  static const heat2 = Color(0xFFEF6C00); // 2-3 people (orange)
  static const heat3 = Color(0xFFC62828); // 4+ people (red)

  static Color risk(String level) => switch (level) {
        'high' => riskHigh,
        'medium' => riskMedium,
        _ => low,
      };

  static Color level(String level) => switch (level) {
        'high' => high,
        'medium' => medium,
        _ => low,
      };

  /// Passability by water depth: green (all traffic) to red (closed).
  static Color depth(String d) => switch (d) {
        'ankle' => low,
        'knee' => medium,
        'waist' => heat2,
        'chest' => high,
        _ => Colors.grey,
      };

  static const levelLabel = {'high': 'উচ্চ', 'medium': 'মাঝারি', 'low': 'কম'};

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: water, surface: surface);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(backgroundColor: surface, foregroundColor: ink, elevation: 0),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: ink),
      ),
    );
  }
}
