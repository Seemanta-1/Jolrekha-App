import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/incident_service.dart';
import '../theme.dart';

/// City-wide numbers: users, problems in the last 30 days, clean-up drives and environmental impact.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final _stats = IncidentService.statsRef.snapshots();
  final _users = AuthService.watchAllUsers();
  final _events = EventService.watchActive();
  late Future<List<Incident>> _incidents = IncidentService.recent(30);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() => _incidents = IncidentService.recent(30)),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _section('পরিবেশে প্রভাব'),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _stats,
            builder: (context, snap) {
              final s = snap.data?.data() ?? {};
              num n(String k) => (s[k] as num?) ?? 0;
              return _tiles([
                ('${n('plasticKg').toStringAsFixed(1)} কেজি', 'প্লাস্টিক তোলা', JR.done),
                ('${n('inletsCleared').toInt()}', 'ড্রেনের মুখ পরিষ্কার', JR.water),
                ('${n('resolved').toInt()}', 'সমস্যার সমাধান', JR.done),
                ('${n('cleanups').toInt()}', 'অভিযান সম্পন্ন', JR.water),
                ('${n('volunteers').toInt()}', 'অভিযানে অংশগ্রহণ', JR.ink),
              ]);
            },
          ),
          _section('ইউজার'),
          StreamBuilder<List<AppUser>>(
            stream: _users,
            builder: (context, snap) {
              final u = snap.data ?? [];
              int c(bool Function(AppUser) f) => u.where(f).length;
              return _tiles([
                ('${u.length}', 'মোট ইউজার', JR.ink),
                ('${c((x) => x.role == Role.citizen && !x.isPending)}', 'নাগরিক', JR.water),
                ('${c((x) => x.role == Role.volunteer)}', 'স্বেচ্ছাসেবক', JR.done),
                ('${c((x) => x.role == Role.authority)}', 'ওয়ার্ড কাউন্সিল', JR.water),
                ('${c((x) => x.isPending)}', 'অনুমোদনের অপেক্ষায়', JR.medium),
              ]);
            },
          ),
          _section('সমস্যা (গত ৩০ দিন)'),
          FutureBuilder<List<Incident>>(
            future: _incidents,
            builder: (context, snap) {
              if (snap.hasError) return Text('${snap.error}');
              if (!snap.hasData) return const LinearProgressIndicator();
              final list = snap.data!;
              final open = list.where((i) => i.status != Status.resolved && i.status != Status.closed).length;
              final byType = <IncidentType, int>{};
              final byArea = <String, int>{};
              for (final i in list) {
                byType.update(i.type, (v) => v + 1, ifAbsent: () => 1);
                byArea.update(i.area, (v) => v + i.weight, ifAbsent: () => i.weight);
              }
              final topAreas = byArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              final maxArea = topAreas.isEmpty ? 1 : topAreas.first.value;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _tiles([
                  ('${list.length}', 'মোট রিপোর্ট হওয়া জায়গা', JR.ink),
                  ('$open', 'খোলা', JR.high),
                  ('${list.where((i) => i.urgent).length}', 'জরুরি (তার/ম্যানহোল)', JR.danger),
                  ('${list.where((i) => i.aiBoost > 0).length}', 'AI যাচাইকৃত ছবি', const Color(0xFF6A3DE8)),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in byType.entries)
                    Chip(avatar: Icon(typeIcon[e.key], size: 16), label: Text('${typeLabel[e.key]}: ${e.value}')),
                ]),
                const SizedBox(height: 12),
                const Text('সবচেয়ে বেশি রিপোর্ট হওয়া এলাকা', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final e in topAreas.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 140, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: e.value / maxArea,
                          minHeight: 10,
                          color: JR.high,
                          backgroundColor: Colors.black12,
                        ),
                      ),
                      SizedBox(width: 48, child: Text(' ${e.value} জন', textAlign: TextAlign.end)),
                    ]),
                  ),
                if (topAreas.isEmpty) const Text('এখনো কোনো রিপোর্ট নেই', style: TextStyle(color: Colors.black54)),
              ]);
            },
          ),
          _section('চলমান অভিযান'),
          StreamBuilder<List<CleanupEvent>>(
            stream: _events,
            builder: (context, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const Text('এখন কোনো অভিযান নেই', style: TextStyle(color: Colors.black54));
              return Column(children: [
                for (final e in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cleaning_services, color: JR.done),
                      title: Text(e.title),
                      subtitle: Text('${e.area} • ${whenBn(e.startAt)} • আয়োজক ${e.createdByName}'),
                      trailing: Text('${e.members.length} জন'),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _tiles(List<(String, String, Color)> items) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (v, l, c) in items)
          SizedBox(
            width: 170,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
                  Text(l, style: const TextStyle(color: Colors.black54)),
                ]),
              ),
            ),
          ),
      ]);
}
