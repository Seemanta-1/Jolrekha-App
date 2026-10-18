import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/incident.dart';
import '../services/auth_service.dart';
import '../services/incident_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';
import '../widgets/resolve_dialog.dart';

class IncidentSheet extends StatelessWidget {
  final Incident incident;
  final AppUser me;
  const IncidentSheet({super.key, required this.incident, required this.me});

  static Future<void> forward(BuildContext context, Incident i, String channel) async {
    final text = IncidentService.summaryBn(i);
    final contact = await IncidentService.contactFor(i.area);
    final Uri uri;
    if (channel == 'email') {
      final to = (contact?['email'] as String?) ?? '';
      final subject = 'জলরেখা: ${i.area} এ ${i.title}';
      uri = Uri.parse('mailto:$to?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}');
    } else {
      final raw = (contact?['phone'] as String?) ?? '';
      // WhatsApp needs the international form: 01XXXXXXXXX -> 8801XXXXXXXXX
      final bd = AuthService.normalizePhone(raw);
      final phone = bd != null ? '88$bd' : raw.replaceAll(RegExp(r'[^0-9]'), '');
      uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) await IncidentService.markForwarded(i, channel);
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      await action();
      nav.pop();
      msg.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('হয়নি: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final canVote = !i.voters.contains(me.uid) && (i.status == Status.resolved || !i.reporters.contains(me.uid));
    final open = i.status != Status.resolved;
    final color = i.isDanger ? JR.danger : (i.status == Status.resolved ? JR.done : JR.water);
    final authorityHere = me.isAuthority && me.covers(i.area);
    final urgentNew = i.urgent && i.status == Status.reported; // danger: authority acts before verification
    final volunteerCanClaim = me.isVolunteer &&
        volunteerFixable.contains(i.type) &&
        (i.status == Status.verified || i.status == Status.acknowledged) &&
        i.assignedTo == null;
    final mineInProgress = i.status == Status.inProgress && i.assignedTo == me.uid;

    Future<void> resolveFlow() async {
      final r = await showResolveDialog(context);
      if (r == null || !context.mounted) return;
      await _run(
        context,
        () => IncidentService.resolve(i, cause: r.cause, plasticKg: r.plasticKg, inlets: r.inlets, note: r.note),
        'সমাধান হিসেবে চিহ্নিত হয়েছে। এলাকার মানুষ নিশ্চিত করলে বন্ধ হবে।',
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(typeIcon[i.type], color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${i.title}${(depthLabel[i.depth] ?? '').isNotEmpty ? ', ${depthLabel[i.depth]} পানি' : ''}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text('${i.area} এর কাছে, প্রথম রিপোর্ট ${timeAgo(i.createdAt)}'),
          if (i.hasDepth)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.water, size: 18, color: JR.depth(i.depth)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(passLabel[i.depth]!,
                      style: TextStyle(fontWeight: FontWeight.w700, color: JR.depth(i.depth))),
                ),
              ]),
            ),
          if (i.hasPhoto || i.ai != null) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (i.hasPhoto) _IncidentPhoto(incident: i),
              const SizedBox(width: 10),
              if (i.ai != null)
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AiBadge(
                        label: i.aiBoost > 0
                            ? 'AI যাচাইকৃত ${(((i.ai!['confidence'] as num?) ?? 0) * 100).round()}%'
                            : 'AI নিশ্চিত নয়',
                        small: true),
                    const SizedBox(height: 4),
                    Text((i.ai!['summary'] as String?) ?? '', style: const TextStyle(fontSize: 12)),
                    if (i.ai!['plastic'] == true)
                      const Text('প্লাস্টিক দেখা গেছে', style: TextStyle(fontSize: 12, color: JR.high)),
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(label: Text(statusLabel[i.status] ?? i.status), backgroundColor: color.withValues(alpha: 0.12)),
            Chip(label: Text('${i.reportCount} জন রিপোর্ট করেছেন')),
            Chip(label: Text('${i.stillThere} জন নিশ্চিত, ${i.gone} জন বলছেন নেই')),
            if (i.aiBoost > 0) const Chip(avatar: Icon(Icons.auto_awesome, size: 16), label: Text('+১ AI নিশ্চিতকরণ')),
            if (i.urgent) const Chip(label: Text('জরুরি'), backgroundColor: Color(0x228E1B5B)),
            if (i.forwardedAt != null) Chip(label: Text('কর্তৃপক্ষকে পাঠানো ${timeAgo(i.forwardedAt)}')),
            if (i.cause != null) Chip(label: Text('কারণ: ${causeLabel[i.cause] ?? i.cause}')),
          ]),
          if (i.isDanger && me.isVolunteer)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('নিরাপত্তা: তার বা ম্যানহোলে স্বেচ্ছাসেবকরা হাত দেবেন না। শুধু দূর থেকে মানুষকে সতর্ক করুন।',
                  style: TextStyle(color: JR.danger)),
            ),
          const Divider(height: 24),

          // crowd review
          if (canVote) ...[
            Text(i.status == Status.resolved ? 'সমস্যাটি কি সত্যিই মিটেছে?' : 'আপনি কি এখানে আছেন?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(context, () => IncidentService.vote(i, stillThere: true, role: me.role),
                      'ধন্যবাদ, নিশ্চিত করা হয়েছে'),
                  child: const Text('এখনো আছে'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(context, () => IncidentService.vote(i, stillThere: false, role: me.role),
                      'ধন্যবাদ, আপডেট করা হয়েছে'),
                  child: Text(i.type == IncidentType.water ? 'পানি নেমে গেছে' : 'আর নেই'),
                ),
              ),
            ]),
          ] else
            const Text('আপনার মত নেওয়া হয়েছে।', style: TextStyle(color: Colors.black54)),

          // forwarding to the ward authority
          if (me.isStaff && (i.isVerified || i.urgent) && open) ...[
            const SizedBox(height: 14),
            Text('ওয়ার্ড কর্তৃপক্ষকে পাঠান', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => forward(context, i, 'whatsapp'),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => forward(context, i, 'email'),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('ইমেইল'),
                ),
              ),
            ]),
          ],

          // authority actions
          if (authorityHere && open && (i.status != Status.reported || i.urgent)) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (i.status == Status.verified || urgentNew)
                FilledButton(
                  onPressed: () => _run(context, () => IncidentService.setStatus(i, Status.acknowledged), 'দেখা হয়েছে'),
                  child: const Text('দেখেছি'),
                ),
              if (i.status == Status.verified || i.status == Status.acknowledged || urgentNew)
                FilledButton(
                  onPressed: () =>
                      _run(context, () => IncidentService.setStatus(i, Status.inProgress), 'কাজ শুরু হিসেবে চিহ্নিত'),
                  child: const Text('কাজ শুরু'),
                ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: JR.done),
                onPressed: resolveFlow,
                child: const Text('সমাধান হয়েছে'),
              ),
            ]),
          ],

          // volunteer actions
          if (volunteerCanClaim) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _run(context, () => IncidentService.setStatus(i, Status.inProgress, claim: true),
                  'দায়িত্ব নেওয়া হয়েছে। ড্রেনের মুখ পরিষ্কার করে "সমাধান হয়েছে" দিন।'),
              icon: const Icon(Icons.volunteer_activism),
              label: const Text('দায়িত্ব নিন'),
            ),
          ],
          if (mineInProgress && !authorityHere) ...[
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: JR.done),
              onPressed: resolveFlow,
              child: const Text('সমাধান হয়েছে'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The report photo, loaded from photos/{id} only when the sheet opens.
class _IncidentPhoto extends StatefulWidget {
  final Incident incident;
  const _IncidentPhoto({required this.incident});

  @override
  State<_IncidentPhoto> createState() => _IncidentPhotoState();
}

class _IncidentPhotoState extends State<_IncidentPhoto> {
  late final _photo = IncidentService.photoFor(widget.incident);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        height: 96,
        child: FutureBuilder<String?>(
          future: _photo,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
            }
            if (snap.data == null) return const Icon(Icons.image_not_supported_outlined, color: Colors.black26);
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(base64Decode(snap.data!), fit: BoxFit.cover),
            );
          },
        ),
      );
}
