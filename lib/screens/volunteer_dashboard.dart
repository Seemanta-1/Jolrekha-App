import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/incident_service.dart';
import '../services/risk_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';
import 'create_event_screen.dart';
import 'events_screen.dart';
import 'incident_sheet.dart';

/// Volunteer dashboard: AI clean-up planner, my drives, and verified problems a team can fix.
class VolunteerDashboard extends StatefulWidget {
  final AppUser me;
  const VolunteerDashboard({super.key, required this.me});

  @override
  State<VolunteerDashboard> createState() => _VolunteerDashboardState();
}

class _VolunteerDashboardState extends State<VolunteerDashboard> {
  final _open = IncidentService.watchOpen();
  final _events = EventService.watchActive();
  List<CleanupSuggestion>? _plan;
  String _planInfo = '';
  bool _planning = false;

  /// AI #5: tomorrow's forecast + smart risk + blocked-drain reports -> where to clean today.
  Future<void> _makePlan() async {
    setState(() => _planning = true);
    final msg = ScaffoldMessenger.of(context);
    List<PlaceRisk> risks = [];
    try {
      final crowd = await IncidentService.watchOpen().first;
      var date = DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
      var rain = 0.0, pCity = 0.0;
      try {
        final tomorrow = (await RiskService.forecast()).last;
        date = tomorrow.date;
        rain = tomorrow.rainMm;
        pCity = tomorrow.pCity;
      } catch (_) {}
      risks = await RiskService.placeRisks(pCity, crowd: crowd);
      _planInfo = 'আগামীকাল ($date) প্রায় ${rain.toStringAsFixed(0)} মিমি বৃষ্টি';
      final plan = await AiService.planCleanups(date: date, rainMm: rain, risks: risks);
      setState(() => _plan = plan.isEmpty ? AiService.fallbackPlan(risks) : plan);
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(aiErrorBn(e))));
      if (risks.isNotEmpty) setState(() => _plan = AiService.fallbackPlan(risks));
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  DateTime _nextAt(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.first) ?? 10, m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, h.clamp(0, 23), m.clamp(0, 59));
    return today.isAfter(now.add(const Duration(minutes: 30))) ? today : today.add(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return Scaffold(
      appBar: AppBar(title: const Text('স্বেচ্ছাসেবকের কাজ')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'volNewEvent',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen(me: me))),
        icon: const Icon(Icons.add),
        label: const Text('নতুন ইভেন্ট'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        // ---- AI planner ----
        Card(
          color: const Color(0xFFF1ECFF),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Expanded(
                  child: Text('অভিযান পরিকল্পনা', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                AiBadge(),
              ]),
              const SizedBox(height: 4),
              const Text('বৃষ্টির পূর্বাভাস, ঝুঁকি মডেল ও ড্রেন বন্ধের রিপোর্ট দেখে AI বলবে আজ কোথায় পরিষ্কার করলে সবচেয়ে কাজে দেবে।',
                  style: TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),
              if (_planning)
                const LinearProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _makePlan,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_plan == null ? 'AI পরামর্শ নিন' : 'আবার পরামর্শ নিন'),
                ),
              if (_plan != null) ...[
                const SizedBox(height: 8),
                Text(_planInfo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                for (final s in _plan!)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.place, color: JR.high),
                      title: Row(children: [
                        Flexible(child: Text('${s.place.area}, ${s.time}')),
                        if (!s.fromAi) const Text('  (মডেল থেকে)', style: TextStyle(fontSize: 11, color: Colors.black45)),
                      ]),
                      subtitle: Text(s.reason),
                      trailing: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateEventScreen(
                              me: me,
                              at: s.place.point,
                              startAt: _nextAt(s.time),
                              title: 'বৃষ্টির আগে ড্রেন পরিষ্কার: ${s.place.area}',
                              description: '${s.reason}\nগ্লাভস ও বস্তা আনুন।',
                              aiSuggested: s.fromAi,
                            ),
                          ),
                        ),
                        child: const Text('ইভেন্ট তৈরি'),
                      ),
                    ),
                  ),
              ],
            ]),
          ),
        ),

        // ---- my drives ----
        StreamBuilder<List<CleanupEvent>>(
          stream: _events,
          builder: (context, snap) {
            final mine = (snap.data ?? []).where((e) => e.isMember(me.uid)).toList();
            if (mine.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              Text('আমার অভিযান', style: Theme.of(context).textTheme.titleMedium),
              for (final e in mine) EventCard(event: e, me: me),
            ]);
          },
        ),

        // ---- verified problems a team can fix ----
        const SizedBox(height: 12),
        Text('এখন যেখানে কাজ দরকার', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        StreamBuilder<List<Incident>>(
          stream: _open,
          builder: (context, snap) {
            final list = (snap.data ?? [])
                .where((i) =>
                    volunteerFixable.contains(i.type) &&
                    (((i.status == Status.verified || i.status == Status.acknowledged) && i.assignedTo == null) ||
                        (i.status == Status.inProgress && i.assignedTo == me.uid)))
                .toList()
              ..sort((a, b) => b.weight.compareTo(a.weight));
            if (list.isEmpty) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline, color: JR.done),
                  title: Text('এই মুহূর্তে যাচাইকৃত কোনো কাজ নেই'),
                  subtitle: Text('উপরের AI পরিকল্পনা থেকে বৃষ্টির আগের অভিযান নিতে পারেন।'),
                ),
              );
            }
            return Column(children: [
              for (final i in list)
                Card(
                  child: ListTile(
                    leading: Icon(typeIcon[i.type], color: JR.water),
                    title: Text('${i.area}: ${i.title}'
                        '${(depthLabel[i.depth] ?? '').isNotEmpty ? ', ${depthLabel[i.depth]} পানি' : ''}'),
                    subtitle: Text('${statusLabel[i.status]}, ${i.weight} জন জানিয়েছেন, ${timeAgo(i.lastReportAt)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => IncidentSheet(incident: i, me: me),
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}
