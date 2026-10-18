import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';
import '../widgets/resolve_dialog.dart';
import 'create_event_screen.dart';
import 'event_chat_screen.dart';

/// Clean-up drives: invitations near me, my teams, and the rest.
class EventsScreen extends StatefulWidget {
  final AppUser me;
  const EventsScreen({super.key, required this.me});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _events = EventService.watchActive();

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return Scaffold(
      appBar: AppBar(title: const Text('পরিষ্কার অভিযান')),
      floatingActionButton: me.isStaff
          ? FloatingActionButton.extended(
              heroTag: 'newEvent',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen(me: me))),
              icon: const Icon(Icons.add),
              label: const Text('নতুন ইভেন্ট'),
            )
          : null,
      body: ValueListenableBuilder<LatLng?>(
        valueListenable: LocationService.position,
        builder: (context, _, __) => StreamBuilder<List<CleanupEvent>>(
          stream: _events,
          builder: (context, snap) {
            final all = snap.data ?? [];
            final invites = EventService.invitationsFor(all, me);
            final mine = all.where((e) => e.isMember(me.uid)).toList();
            final others = all.where((e) => !e.isMember(me.uid) && !invites.contains(e)).toList();
            if (snap.connectionState == ConnectionState.waiting && all.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              if (all.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.event_available, color: JR.done),
                    title: Text('এখন কোনো অভিযান নেই'),
                    subtitle: Text('স্বেচ্ছাসেবকরা নতুন অভিযান দিলে আপনার কাছে আমন্ত্রণ আসবে।'),
                  ),
                ),
              if (invites.isNotEmpty) ...[
                _header(context, 'আপনার কাছে আমন্ত্রণ', Icons.notifications_active_outlined),
                for (final e in invites) EventCard(event: e, me: me),
              ],
              if (mine.isNotEmpty) ...[
                _header(context, 'আমার টিম', Icons.groups),
                for (final e in mine) EventCard(event: e, me: me),
              ],
              if (others.isNotEmpty) ...[
                _header(context, 'অন্যান্য অভিযান', Icons.event_outlined),
                for (final e in others) EventCard(event: e, me: me),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(children: [
          Icon(icon, size: 18, color: JR.water),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}

class EventCard extends StatelessWidget {
  final CleanupEvent event;
  final AppUser me;
  const EventCard({super.key, required this.event, required this.me});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final km = LocationService.kmTo(e.point);
    final member = e.isMember(me.uid);
    final organiser = e.createdBy == me.uid;
    final msg = ScaffoldMessenger.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cleaning_services, color: JR.done),
            const SizedBox(width: 8),
            Expanded(child: Text(e.title, style: Theme.of(context).textTheme.titleMedium)),
            if (e.aiSuggested) const AiBadge(label: 'AI পরিকল্পনা', small: true),
          ]),
          const SizedBox(height: 4),
          Text('${e.area} • ${whenBn(e.startAt)}${km == null ? '' : ' • ${km.toStringAsFixed(1)} কিমি'}',
              style: const TextStyle(color: Colors.black87)),
          Text('আয়োজক: ${e.createdByName} • ${e.members.length} জন যোগ দিয়েছেন',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.description),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (member)
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => EventChatScreen(event: e, me: me))),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('টিম চ্যাট'),
              )
            else ...[
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await EventService.join(e);
                    msg.showSnackBar(const SnackBar(content: Text('টিমে যোগ দিয়েছেন! +১০ পয়েন্ট')));
                  } catch (err) {
                    msg.showSnackBar(SnackBar(content: Text('হয়নি: $err')));
                  }
                },
                icon: const Icon(Icons.group_add),
                label: const Text('যোগ দিন'),
              ),
              if (!me.dismissedEvents.contains(e.id))
                TextButton(onPressed: () => AuthService.dismissEvent(e.id), child: const Text('না, ধন্যবাদ')),
            ],
            if (organiser)
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await showResolveDialog(context, askCause: false);
                  if (r == null) return;
                  try {
                    await EventService.complete(e, plasticKg: r.plasticKg, inlets: r.inlets);
                    msg.showSnackBar(const SnackBar(content: Text('অভিযান সম্পন্ন! প্রভাব লিডারবোর্ডে যোগ হয়েছে।')));
                  } catch (err) {
                    msg.showSnackBar(SnackBar(content: Text('হয়নি: $err')));
                  }
                },
                icon: const Icon(Icons.task_alt),
                label: const Text('অভিযান শেষ'),
              ),
          ]),
        ]),
      ),
    );
  }
}
