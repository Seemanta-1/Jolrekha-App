import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'approvals_page.dart';
import 'contacts_page.dart';
import 'overview_page.dart';
import 'users_page.dart';

/// Admin website shell: side navigation on wide screens, bottom bar on phones.
class AdminHome extends StatefulWidget {
  final AppUser me;
  const AdminHome({super.key, required this.me});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;
  int _pending = 0;
  late final StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _sub = AuthService.watchPending().listen((p) => setState(() => _pending = p.length));
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Widget _badge(IconData icon, int n) => n > 0 ? Badge(label: Text('$n'), child: Icon(icon)) : Icon(icon);

  @override
  Widget build(BuildContext context) {
    final pages = <(String, Widget, Widget)>[
      ('ওভারভিউ', const Icon(Icons.dashboard_outlined), const OverviewPage()),
      ('অনুমোদন', _badge(Icons.how_to_reg_outlined, _pending), const ApprovalsPage()),
      ('সব ইউজার', const Icon(Icons.people_outline), UsersPage(me: widget.me)),
      ('ওয়ার্ড যোগাযোগ', const Icon(Icons.contact_phone_outlined), const ContactsPage()),
    ];
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = IndexedStack(index: _index, children: [for (final p in pages) p.$3]);
    return Scaffold(
      appBar: AppBar(
        title: Text('জলরেখা অ্যাডমিন • ${pages[_index].$1}'),
        actions: [
          Center(child: Text(widget.me.name, style: const TextStyle(color: JR.ink))),
          const IconButton(tooltip: 'লগআউট', onPressed: AuthService.signOut, icon: Icon(Icons.logout)),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                destinations: [for (final p in pages) NavigationRailDestination(icon: p.$2, label: Text(p.$1))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [for (final p in pages) NavigationDestination(icon: p.$2, label: p.$1)],
            ),
    );
  }
}
