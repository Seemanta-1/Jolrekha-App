import 'dart:async';

import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/incident_service.dart';
import '../services/location_service.dart';
import '../widgets/rewards.dart';
import 'council_dashboard.dart';
import 'events_screen.dart';
import 'impact_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'volunteer_dashboard.dart';

/// Each role gets its own dashboard:
/// citizen: Map, Events, Impact, Profile; volunteer: + Volunteer dashboard;
/// ward council: + Ward dashboard; admin: + Ward (approvals live on the admin website).
/// Also delivers the free, in-app notifications: nearby clean-up invitations pop up,
/// and badges show new ward problems and pending registrations.
class HomeShell extends StatefulWidget {
  final AppUser me;
  const HomeShell({super.key, required this.me});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  List<CleanupEvent> _events = [];
  List<Incident> _incidents = [];
  final _shown = <String>{}; // invitations already popped up in this session
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    LocationService.start();
    LocationService.position.addListener(_maybeInvite);
    _subs.add(EventService.watchActive().listen((e) {
      setState(() => _events = e);
      _maybeInvite();
    }));
    _subs.add(IncidentService.watchOpen().listen((i) => setState(() => _incidents = i)));
    WidgetsBinding.instance.addPostFrameCallback((_) => claimVerifiedBonus(context));
  }

  @override
  void dispose() {
    LocationService.position.removeListener(_maybeInvite);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  List<CleanupEvent> get _invites => EventService.invitationsFor(_events, widget.me);

  /// New verified or urgent problems in the council's areas during the last 24 hours.
  int get _wardNew => _incidents
      .where((i) =>
          widget.me.covers(i.area) &&
          (i.status == Status.verified || (i.urgent && i.status == Status.reported)) &&
          (i.createdAt ?? DateTime.now()).isAfter(DateTime.now().subtract(const Duration(hours: 24))))
      .length;

  /// The free "push": a clean-up drive near me pops up while the app is open.
  void _maybeInvite() {
    if (!mounted) return;
    final next = _invites.where((e) => !_shown.contains(e.id)).toList();
    if (next.isEmpty) return;
    _shown.addAll(next.map((e) => e.id)); // one popup at a time; the rest wait in the Events tab
    final e = next.first;
    final km = LocationService.kmTo(e.point);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cleaning_services, size: 36),
          title: const Text('আপনার কাছে পরিষ্কার অভিযান'),
          content: Text('${e.title}\n${e.area}, ${whenBn(e.startAt)}'
              '${km == null ? '' : ' (${km.toStringAsFixed(1)} কিমি দূরে)'}\n'
              'আয়োজক: ${e.createdByName}, ${e.members.length} জন যোগ দিয়েছেন।'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                AuthService.dismissEvent(e.id);
              },
              child: const Text('না, ধন্যবাদ'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('পরে')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await EventService.join(e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('আপনি টিমে যোগ দিয়েছেন। ইভেন্ট ট্যাব থেকে টিম চ্যাট খুলুন।')),
                  );
                }
              },
              child: const Text('যোগ দিন'),
            ),
          ],
        ),
      );
    });
  }

  Widget _icon(IconData icon, int count) =>
      count > 0 ? Badge(label: Text('$count'), child: Icon(icon)) : Icon(icon);

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final tabs = <(Widget, NavigationDestination)>[
      (MapScreen(me: me), const NavigationDestination(icon: Icon(Icons.map_outlined), label: 'ম্যাপ')),
      if (me.isAuthority)
        (CouncilDashboard(me: me), NavigationDestination(icon: _icon(Icons.account_balance_outlined, _wardNew), label: 'ওয়ার্ড')),
      if (me.role == Role.volunteer)
        (VolunteerDashboard(me: me), const NavigationDestination(icon: Icon(Icons.volunteer_activism_outlined), label: 'কাজ')),
      (EventsScreen(me: me), NavigationDestination(icon: _icon(Icons.groups_outlined, _invites.length), label: 'ইভেন্ট')),
      (const ImpactScreen(), const NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'লিডারবোর্ড')),
      (ProfileScreen(me: me), const NavigationDestination(icon: Icon(Icons.person_outline), label: 'প্রোফাইল')),
    ];
    final i = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: IndexedStack(index: i, children: [for (final t in tabs) t.$1]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) {
          setState(() => _index = v);
          // tabs are built once, so pay verified-report bonuses whenever the points are opened
          if (tabs[v].$1 is ImpactScreen || tabs[v].$1 is ProfileScreen) claimVerifiedBonus(context);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [for (final t in tabs) t.$2],
      ),
    );
  }
}
