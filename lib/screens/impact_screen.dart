import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/incident.dart';
import '../services/auth_service.dart';
import '../services/incident_service.dart';
import '../services/points_service.dart';
import '../theme.dart';
import '../widgets/rewards.dart';

/// Leaderboard with monthly prizes, and the city-wide environmental impact.
class ImpactScreen extends StatelessWidget {
  const ImpactScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('লিডারবোর্ড ও প্রভাব'),
            bottom: const TabBar(tabs: [Tab(text: 'লিডারবোর্ড'), Tab(text: 'পরিবেশে প্রভাব')]),
          ),
          body: const TabBarView(children: [_Leaderboard(), _Impact()]),
        ),
      );
}

class _Leaderboard extends StatefulWidget {
  const _Leaderboard();

  @override
  State<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<_Leaderboard> {
  bool _monthly = true;
  late Stream<List<LeaderRow>> _rows = PointsService.top(monthly: true);
  final _mine = PointsService.mine(AuthService.uid);

  static const _medal = [Color(0xFFD4A017), Color(0xFF9EA7AD), Color(0xFFB0703C)];

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        StreamBuilder<PlayerStats>(
          stream: _mine,
          builder: (context, snap) => LevelCard(stats: snap.data ?? PlayerStats(const {})),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('মাসের সেরা পুরস্কার', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (var i = 0; i < Points.prizes.length; i++)
                Text('${['১ম', '২য়', '৩য়'][i]}: ${Points.prizes[i]}', style: TextStyle(color: _medal[i])),
              const SizedBox(height: 6),
              const Text(
                'পয়েন্ট: রিপোর্ট +${Points.report}, রিপোর্ট যাচাই হলে +${Points.verified} '
                '(নির্ভুলতা বেশি হলে +${Points.accurateVerified}), AI যাচাইকৃত ছবি +${Points.aiPhoto}, যাচাই ভোট +${Points.vote}, '
                'অভিযানে যোগ +${Points.joinEvent}, অভিযান আয়োজন +${Points.organizeEvent}, সমাধান +${Points.resolve}',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('এই মাস')),
            ButtonSegment(value: false, label: Text('সর্বকালের')),
          ],
          selected: {_monthly},
          onSelectionChanged: (s) => setState(() {
            _monthly = s.first;
            _rows = PointsService.top(monthly: _monthly);
          }),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<LeaderRow>>(
          stream: _rows,
          builder: (context, snap) {
            if (snap.hasError) return Text('${snap.error}');
            final rows = (snap.data ?? []).where((r) => r.points > 0).toList();
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('এখনো কেউ পয়েন্ট পায়নি। প্রথম রিপোর্ট করে শীর্ষে উঠুন!', textAlign: TextAlign.center),
              );
            }
            return Column(children: [
              for (var i = 0; i < rows.length; i++)
                Card(
                  color: rows[i].uid == AuthService.uid ? const Color(0xFFE6F1F8) : null,
                  child: ListTile(
                    leading: i < 3
                        ? Icon(Icons.emoji_events, color: _medal[i], size: 32)
                        : CircleAvatar(radius: 16, child: Text('${i + 1}')),
                    title: Text(rows[i].name),
                    subtitle: Text('${Role.label[rows[i].role] ?? ''} • ${Points.badge(rows[i].points)}'
                        '${_monthly && i < 3 ? '\nপুরস্কার: ${Points.prizes[i]}' : ''}'),
                    trailing: Text('${rows[i].points}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: JR.ink)),
                  ),
                ),
            ]);
          },
        ),
      ]);
}

class _Impact extends StatelessWidget {
  const _Impact();

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: IncidentService.statsRef.snapshots(),
        builder: (context, snap) {
          final s = snap.data?.data() ?? {};
          num n(String k) => (s[k] as num?) ?? 0;
          final causes = {
            for (final k in causeLabel.keys)
              if (n('cause_$k') > 0) k: n('cause_$k').toInt(),
          };
          final totalCauses = causes.values.fold<int>(0, (a, b) => a + b);

          return ListView(padding: const EdgeInsets.all(16), children: [
            _big('${n('plasticKg').toStringAsFixed(1)} কেজি', 'প্লাস্টিক ও বর্জ্য ড্রেন থেকে তোলা হয়েছে, যা খাল হয়ে নদীতে যেত'),
            _big('${n('inletsCleared').toInt()}টি', 'ড্রেনের মুখ পরিষ্কার হয়েছে'),
            _big('${n('resolved').toInt()}টি', 'জলাবদ্ধতা ও ঝুঁকির সমাধান'),
            _big('${n('cleanups').toInt()}টি', 'পরিষ্কার অভিযান সম্পন্ন'),
            _big('${n('volunteers').toInt()} জন', 'অভিযানে অংশ নিয়েছেন'),
            const SizedBox(height: 16),
            Text('পানি কেন জমছে', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (totalCauses == 0)
              const Text('সমাধানের সময় কারণ লেখা হলে এখানে দেখা যাবে।', style: TextStyle(color: Colors.black54)),
            for (final e in (causes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${causeLabel[e.key]}: ${e.value}টি'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: e.value / totalCauses,
                    minHeight: 8,
                    color: e.key == 'plastic' ? JR.high : JR.water,
                    backgroundColor: Colors.black12,
                  ),
                ]),
              ),
          ]);
        },
      );

  Widget _big(String value, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 120,
            child: Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: JR.ink)),
          ),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.black87))),
        ]),
      );
}
