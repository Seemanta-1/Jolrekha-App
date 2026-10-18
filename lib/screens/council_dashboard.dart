import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/incident.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/incident_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';
import 'incident_sheet.dart';

/// Ward council dashboard: every problem citizens marked in the council's areas, the most-reported
/// spots first, and an AI weekly report. Unverified single reports are counted but kept out of the work list,
/// except danger (wire, manhole) which comes at once.
class CouncilDashboard extends StatefulWidget {
  final AppUser me;
  const CouncilDashboard({super.key, required this.me});

  @override
  State<CouncilDashboard> createState() => _CouncilDashboardState();
}

class _CouncilDashboardState extends State<CouncilDashboard> {
  final _open = IncidentService.watchOpen();
  bool _aiBusy = false;

  Future<void> _aiReport() async {
    setState(() => _aiBusy = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      final list = (await IncidentService.recent(7)).where((i) => widget.me.covers(i.area)).toList();
      final text = await AiService.councilReport(list, widget.me.areas);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Expanded(child: Text('সাপ্তাহিক প্রতিবেদন')),
            AiBadge(label: 'AI লিখেছে'),
          ]),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('কপি হয়েছে')));
              },
              child: const Text('কপি'),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
                  mode: LaunchMode.externalApplication),
              child: const Text('WhatsApp'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('বন্ধ')),
          ],
        ),
      );
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(aiErrorBn(e))));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return Scaffold(
      appBar: AppBar(
        title: Text(me.areas.isEmpty ? 'ওয়ার্ড ড্যাশবোর্ড (সব এলাকা)' : 'ওয়ার্ড: ${me.areas.join(', ')}'),
      ),
      body: StreamBuilder<List<Incident>>(
        stream: _open,
        builder: (context, snap) {
          final all = (snap.data ?? []).where((i) => me.covers(i.area)).toList();
          final work = all
              .where((i) =>
                  (i.isVerified && i.status != Status.resolved) || (i.urgent && i.status == Status.reported))
              .toList()
            ..sort((a, b) {
              if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
              return b.weight.compareTo(a.weight); // most-reported first
            });
          final pending = all.where((i) => i.status == Status.reported && !i.urgent).length;
          final resolved = all.where((i) => i.status == Status.resolved).length;
          final byType = <IncidentType, int>{};
          for (final i in all) {
            byType.update(i.type, (v) => v + 1, ifAbsent: () => 1);
          }

          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              _stat('কাজ বাকি', '${work.length}', JR.high),
              _stat('যাচাই চলছে', '$pending', JR.medium),
              _stat('সমাধান', '$resolved', JR.done),
            ]),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFFF1ECFF),
              child: ListTile(
                leading: const Icon(Icons.auto_awesome, color: Color(0xFF6A3DE8)),
                title: const Row(children: [
                  Flexible(child: Text('সাপ্তাহিক প্রতিবেদন')),
                  SizedBox(width: 6),
                  AiBadge(small: true),
                ]),
                subtitle: const Text('গত ৭ দিনের রিপোর্ট থেকে AI সমস্যা, মূল কারণ ও করণীয় লিখে দেবে'),
                trailing: _aiBusy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton(onPressed: _aiReport, child: const Text('তৈরি')),
              ),
            ),
            if (byType.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('এলাকার সমস্যা (গত ৩ দিন)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in byType.entries)
                  Chip(
                    avatar: Icon(typeIcon[e.key], size: 16, color: dangerTypes.contains(e.key) ? JR.danger : JR.water),
                    label: Text('${typeLabel[e.key]}: ${e.value}'),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            Text('কাজের তালিকা (বেশি রিপোর্ট আগে)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (work.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline, color: JR.done),
                  title: Text('আপনার এলাকায় এখন কোনো যাচাইকৃত সমস্যা নেই'),
                ),
              ),
            for (final i in work)
              Card(
                child: ListTile(
                  leading: Icon(typeIcon[i.type], color: i.isDanger ? JR.danger : JR.water),
                  title: Text('${i.area}: ${i.title}'
                      '${(depthLabel[i.depth] ?? '').isNotEmpty ? ' (${depthLabel[i.depth]})' : ''}'),
                  subtitle: Text('${statusLabel[i.status]}, ${i.weight} জন জানিয়েছেন, ${timeAgo(i.createdAt)}'
                      '${i.aiBoost > 0 ? ' • AI যাচাইকৃত ছবি' : ''}'),
                  trailing: i.urgent ? const Chip(label: Text('জরুরি')) : const Icon(Icons.chevron_right),
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
    );
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c)),
              Text(label, style: const TextStyle(color: JR.ink)),
            ]),
          ),
        ),
      );
}
