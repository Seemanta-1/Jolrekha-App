import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/incident.dart';
import 'risk_service.dart';

/// AI #1: what the photo shows.
class PhotoAnalysis {
  final bool relevant;
  final IncidentType type;
  final String depth;
  final bool plastic;
  final double confidence;
  final String summary;

  PhotoAnalysis(this.relevant, this.type, this.depth, this.plastic, this.confidence, this.summary);

  /// Trusted enough to count as one extra confirmation.
  bool get trusted => relevant && confidence >= AppConfig.aiMinConfidence;

  Map<String, dynamic> toMap() => {
        'relevant': relevant,
        'type': type.name,
        'depth': depth,
        'plastic': plastic,
        'confidence': confidence,
        'summary': summary,
        'model': AppConfig.aiModel,
      };
}

/// AI #5: one suggested clean-up drive.
class CleanupSuggestion {
  final Place place;
  final String time; // HH:mm
  final String reason;
  final bool fromAi;
  CleanupSuggestion(this.place, this.time, this.reason, {this.fromAi = true});
}

/// Gemini through Firebase AI Logic: no server and no API key in the app.
class AiService {
  /// Low thinking keeps answers fast (a photo takes ~5 s instead of ~8 s) with the same accuracy in tests.
  static GenerativeModel _model({Schema? schema, double temperature = 0.2}) =>
      FirebaseAI.googleAI().generativeModel(
        model: AppConfig.aiModel,
        generationConfig: GenerationConfig(
          temperature: temperature,
          responseMimeType: schema == null ? null : 'application/json',
          responseSchema: schema,
          thinkingConfig: ThinkingConfig.withThinkingLevel(ThinkingLevel.low),
        ),
      );

  static const _photoTimeout = Duration(seconds: 25);
  static const _textTimeout = Duration(seconds: 45);

  // ---------------- AI #1: photo report ----------------

  static final _photoSchema = Schema.object(properties: {
    'relevant': Schema.boolean(),
    'type': Schema.enumString(enumValues: IncidentType.values.map((t) => t.name).toList()),
    'depth': Schema.enumString(enumValues: ['none', 'ankle', 'knee', 'waist', 'chest']),
    'plastic_visible': Schema.boolean(),
    'confidence': Schema.number(),
    'summary_bn': Schema.string(),
  });

  static Future<PhotoAnalysis> analyzePhoto(Uint8List bytes, String mimeType) async {
    const prompt = '''
You check citizen reports for JolRekha, a Dhaka (Bangladesh) app for waterlogging and street problems.
Look at the photo and fill the JSON:
- relevant: true only if the photo clearly shows a real public street or environmental problem.
  Selfies, indoor photos, screenshots, food, documents or unrelated pictures are NOT relevant.
- type: water (waterlogged or flooded street), wire (electric wire in or near water, or a fallen live wire),
  manhole (open or broken manhole), garbage (drain blocked by plastic or garbage, waste dumped on the street),
  pothole (broken road or footpath), tree (fallen tree), streetlight (broken street light),
  other (any other public problem).
- depth: for water, how deep compared with a person: ankle, knee, waist, chest; otherwise none.
- plastic_visible: true if plastic, polythene or bottles are visible in the water or drains.
- confidence: 0 to 1, how sure you are about relevant and type.
- summary_bn: one short sentence in Bangla describing what you see.''';
    final res = await _model(schema: _photoSchema).generateContent([
      Content.multi([const TextPart(prompt), InlineDataPart(mimeType, bytes)]),
    ]).timeout(_photoTimeout);
    final j = jsonDecode(res.text ?? '{}') as Map<String, dynamic>;
    return PhotoAnalysis(
      j['relevant'] == true,
      IncidentType.values.firstWhere((t) => t.name == j['type'], orElse: () => IncidentType.other),
      (j['depth'] as String?) ?? 'none',
      j['plastic_visible'] == true,
      ((j['confidence'] as num?) ?? 0).toDouble().clamp(0, 1).toDouble(),
      (j['summary_bn'] as String?) ?? '',
    );
  }

  // ---------------- AI #3: weekly report for the ward council ----------------

  static Future<String> councilReport(List<Incident> incidents, List<String> areas) async {
    final byType = <String, int>{}, byArea = <String, int>{}, causes = <String, int>{};
    var open = 0, resolved = 0, urgent = 0, plastic = 0;
    for (final i in incidents) {
      byType.update(typeLabel[i.type]!, (v) => v + 1, ifAbsent: () => 1);
      byArea.update(i.area, (v) => v + i.weight, ifAbsent: () => i.weight);
      if (i.cause != null) causes.update(causeLabel[i.cause] ?? i.cause!, (v) => v + 1, ifAbsent: () => 1);
      if (i.status == Status.resolved || i.status == Status.closed) {
        resolved++;
      } else {
        open++;
      }
      if (i.urgent) urgent++;
      if (i.ai?['plastic'] == true) plastic++;
    }
    final worst = [...incidents]..sort((a, b) => b.weight.compareTo(a.weight));
    final data = {
      'areas': areas.isEmpty ? 'সব এলাকা' : areas,
      'period': 'গত ৭ দিন',
      'total_incidents': incidents.length,
      'open': open,
      'resolved_or_closed': resolved,
      'urgent_danger': urgent,
      'photos_with_plastic_seen_by_ai': plastic,
      'by_type': byType,
      'people_reporting_by_area': byArea,
      'causes_recorded_when_resolved': causes,
      'top_spots': [
        for (final i in worst.take(5))
          {
            'area': i.area,
            'problem': i.title,
            if (i.depth != 'none') 'depth': depthLabel[i.depth],
            'people': i.weight,
            'status': statusLabel[i.status],
            'map': 'https://maps.google.com/?q=${i.lat.toStringAsFixed(5)},${i.lon.toStringAsFixed(5)}',
          },
      ],
    };
    final prompt = '''
তুমি ঢাকার একটি ওয়ার্ড কাউন্সিলের জন্য "জলরেখা" অ্যাপের সাপ্তাহিক প্রতিবেদন লেখো।
নিচের ডেটা নাগরিকদের রিপোর্ট থেকে নেওয়া। শুধু এই ডেটার সংখ্যা ব্যবহার করবে, নতুন সংখ্যা বানাবে না।
আনুষ্ঠানিক সহজ বাংলায়, ছোট শিরোনাম দিয়ে লেখো:
১. সারসংক্ষেপ (২-৩ লাইন)
২. প্রধান সমস্যা (ধরন ও সংখ্যা)
৩. মূল কারণ (প্লাস্টিক, নির্মাণসামগ্রী ইত্যাদি, ডেটায় যা আছে)
৪. সবচেয়ে ঝুঁকিপূর্ণ জায়গা (ম্যাপ লিংকসহ)
৫. করণীয়: ৩টি নির্দিষ্ট সুপারিশ, কোনটা আগে
ডেটা না থাকলে সেটাই সংক্ষেপে বলো। ২০০ শব্দের মধ্যে রাখো। Markdown চিহ্ন (#, *) ব্যবহার করবে না।

ডেটা:
${const JsonEncoder.withIndent(' ').convert(data)}''';
    final res = await _model(temperature: 0.4).generateContent([Content.text(prompt)]).timeout(_textTimeout);
    return (res.text ?? '').trim();
  }

  // ---------------- AI #5: clean-up planner ----------------

  static Future<List<CleanupSuggestion>> planCleanups({
    required String date,
    required double rainMm,
    required List<PlaceRisk> risks,
  }) async {
    final candidates = risks.take(10).toList();
    final schema = Schema.array(
      items: Schema.object(properties: {
        'area': Schema.enumString(enumValues: candidates.map((r) => r.place.area).toList()),
        'time': Schema.string(description: 'HH:mm, 24-hour, Dhaka time'),
        'reason_bn': Schema.string(),
      }),
    );
    final data = [
      for (final r in candidates)
        {
          'area': r.place.area,
          'risk_level': r.level,
          'risk': double.parse(r.risk.toStringAsFixed(3)),
          'past_waterlogging_share': r.place.pPlace,
          'open_drain_blocked_reports': r.drainReports,
          'open_waterlogging_reports': r.waterNow,
        },
    ];
    final prompt = '''
You plan volunteer clean-up drives for JolRekha in Dhaka. Volunteers clear drain inlets of plastic and waste
before rain so streets do not flood. Forecast for $date: ${rainMm.toStringAsFixed(0)} mm of rain.
Pick up to 3 places where a drive today helps most: high risk first, blocked drains matter most,
places already under water are less useful (it is too late there). Suggest a safe daytime time (08:00-17:00)
before the rain. reason_bn: one short Bangla sentence a volunteer understands.
Places:
${jsonEncode(data)}''';
    final res = await _model(schema: schema).generateContent([Content.text(prompt)]).timeout(_textTimeout);
    final list = jsonDecode(res.text ?? '[]') as List;
    final byArea = {for (final r in candidates) r.place.area: r.place};
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        if (byArea[e['area']] != null)
          CleanupSuggestion(byArea[e['area']]!, (e['time'] as String?) ?? '10:00', (e['reason_bn'] as String?) ?? ''),
    ].take(3).toList();
  }

  /// Used when the AI is unavailable: the top risk places from the model.
  static List<CleanupSuggestion> fallbackPlan(List<PlaceRisk> risks) => [
        for (final r in risks.take(3))
          CleanupSuggestion(
            r.place,
            '10:00',
            'ঝুঁকি ${r.level == 'high' ? 'উচ্চ' : r.level == 'medium' ? 'মাঝারি' : 'কম'}${r.why.isEmpty ? '' : ', ${r.why}'}',
            fromAi: false,
          ),
      ];
}

/// Readable AI error for a snackbar.
String aiErrorBn(Object e) {
  final s = '$e';
  if (s.contains('not been used') || s.contains('disabled') || s.contains('PERMISSION_DENIED')) {
    return 'AI চালু নেই: Firebase console → AI Logic → Get started করুন';
  }
  if (s.contains('not found') || s.contains('NOT_FOUND')) return 'AI মডেল পাওয়া যায়নি (config.dart এ aiModel দেখুন)';
  if (s.contains('quota') || s.contains('RESOURCE_EXHAUSTED')) return 'AI এর ফ্রি সীমা শেষ, একটু পরে চেষ্টা করুন';
  if (s.contains('App Check')) return 'AI বন্ধ: Firebase console এ AI Logic এর App Check enforcement বন্ধ করুন';
  if (e is TimeoutException) return 'AI সময়মতো উত্তর দেয়নি (ইন্টারনেট ধীর?)';
  return 'AI কাজ করেনি: ${s.length > 120 ? s.substring(0, 120) : s}';
}
