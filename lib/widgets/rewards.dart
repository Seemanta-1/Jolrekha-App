import 'package:flutter/material.dart';

import '../config.dart';
import '../services/points_service.dart';
import '../theme.dart';

class Achievement {
  final IconData icon;
  final String name, how;
  final bool Function(PlayerStats s) earned;
  const Achievement(this.icon, this.name, this.how, this.earned);
}

/// Badges unlocked by what a person has done, not only by points.
final achievements = [
  Achievement(Icons.flag, 'প্রথম রিপোর্ট', '১টি রিপোর্ট করুন', (s) => s.reports >= 1),
  Achievement(Icons.verified, 'সত্যবাদী', '৫টি রিপোর্ট যাচাই হোক', (s) => s.verified >= 5),
  Achievement(Icons.center_focus_strong, 'নির্ভুল চোখ',
      '${Points.accurateMinReports}+ রিপোর্টে ${(Points.accurateRate * 100).round()}% নির্ভুল', (s) => s.isAccurate),
  Achievement(Icons.how_to_vote, 'যাচাইকারী', '২০টি ভোট দিন', (s) => s.votes >= 20),
  Achievement(Icons.build_circle, 'সমাধানকারী', '৫টি সমস্যার সমাধান', (s) => s.resolved >= 5),
  Achievement(Icons.recycling, 'ড্রেন যোদ্ধা', '১০ কেজি প্লাস্টিক তুলুন', (s) => s.plasticKg >= 10),
  Achievement(Icons.groups, 'দলের খেলোয়াড়', '৩টি অভিযানে যোগ দিন', (s) => s.events >= 3),
  Achievement(Icons.campaign, 'আয়োজক', '১টি অভিযান শেষ করুন', (s) => s.organized >= 1),
];

String _bn(int n) => '$n'.split('').map((c) => '০১২৩৪৫৬৭৮৯'[int.parse(c)]).join();

/// Points, level and progress to the next level, with accuracy.
class LevelCard extends StatelessWidget {
  final PlayerStats stats;
  const LevelCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final next = Points.nextLevel(s.total);
    final from = Points.levels.lastWhere((l) => s.total >= l.$1).$1;
    final acc = s.accuracy;
    return Card(
      color: JR.ink,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.stars, color: Color(0xFFD4A017), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('আমার পয়েন্ট: ${s.total}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                Text('এই মাসে ${s.month} • লেভেল: ${Points.badge(s.total)}',
                    style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: next == null ? 1 : (s.total - from) / (next.$1 - from),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFD4A017),
            backgroundColor: Colors.white24,
          ),
          const SizedBox(height: 4),
          Text(
            next == null ? 'সর্বোচ্চ লেভেলে পৌঁছেছেন!' : '"${next.$2}" হতে আর ${next.$1 - s.total} পয়েন্ট',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (acc != null) ...[
            const SizedBox(height: 8),
            Text(
              'নির্ভুলতা ${(acc * 100).round()}% (${s.verified}/${s.reports} রিপোর্ট যাচাই হয়েছে)'
              '${s.isAccurate ? ' • যাচাই বোনাস ×১.৫' : ''}',
              style: TextStyle(color: s.isAccurate ? const Color(0xFF8FE3B0) : Colors.white70, fontSize: 12),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Earned badges in colour, locked ones grey with how to get them.
class BadgeGrid extends StatelessWidget {
  final PlayerStats stats;
  const BadgeGrid({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final got = achievements.where((a) => a.earned(stats)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ব্যাজ (${_bn(got)}/${_bn(achievements.length)})', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in achievements)
          Tooltip(
            message: a.how,
            triggerMode: TooltipTriggerMode.tap,
            child: SizedBox(
              width: 76,
              child: Column(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: a.earned(stats) ? const Color(0xFFFFF3D0) : Colors.black12,
                  child: Icon(a.icon, color: a.earned(stats) ? const Color(0xFFD4A017) : Colors.black38),
                ),
                const SizedBox(height: 4),
                Text(a.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: a.earned(stats) ? JR.ink : Colors.black45)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      const Text('লক করা ব্যাজে ট্যাপ করে দেখুন কীভাবে পাবেন', style: TextStyle(fontSize: 11, color: Colors.black45)),
    ]);
  }
}

/// Pays any pending verified-report bonus and tells the person.
Future<void> claimVerifiedBonus(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  try {
    final (n, pts) = await PointsService.claimVerified();
    if (n > 0) msg.showSnackBar(SnackBar(content: Text('আপনার $nটি রিপোর্ট যাচাই হয়েছে! +$pts পয়েন্ট')));
  } catch (e) {
    debugPrint('claimVerified failed: $e'); // the bonus is paid on the next visit
  }
}
