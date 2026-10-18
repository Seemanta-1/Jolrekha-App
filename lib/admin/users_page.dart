import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/risk_service.dart';
import '../theme.dart';

/// Everyone in the app: search, change role, set a council's areas, suspend.
class UsersPage extends StatefulWidget {
  final AppUser me;
  const UsersPage({super.key, required this.me});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _users = AuthService.watchAllUsers();
  String _query = '';
  String? _role; // null = all

  Future<void> _act(Future<void> Function() f, String done) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await f();
      msg.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('হয়নি: $e')));
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('হ্যাঁ')),
          ],
        ),
      ) ??
      false;

  Future<void> _editAreas(AppUser u) async {
    final all = (await RiskService.places()).map((p) => p.area).toList()..sort();
    if (!mounted) return;
    final picked = {...u.areas};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('${u.name}: দায়িত্বের এলাকা'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in all)
                  FilterChip(
                    label: Text(a),
                    selected: picked.contains(a),
                    onSelected: (v) => setS(() => v ? picked.add(a) : picked.remove(a)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('সেভ')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _act(() => AuthService.setAreas(u, picked.toList()..sort()), 'এলাকা সেভ হয়েছে');
    }
  }

  Future<void> _menu(AppUser u, String action) async {
    if (action.startsWith('role:')) {
      final role = action.substring(5);
      if (!await _confirm('${u.name} কে "${Role.label[role]}" করবেন?')) return;
      await _act(() => AuthService.setRole(u, role), '${u.name} এখন ${Role.label[role]}');
    } else if (action == 'areas') {
      await _editAreas(u);
    } else if (action == 'suspend') {
      if (!await _confirm('${u.name} এর অ্যাকাউন্ট সাময়িক বন্ধ করবেন?')) return;
      await _act(() => AuthService.setSuspended(u, true), 'বন্ধ করা হয়েছে');
    } else if (action == 'restore') {
      await _act(() => AuthService.setSuspended(u, false), 'আবার চালু হয়েছে');
    }
  }

  static String _statusLabel(String s) => switch (s) {
        Approval.pending => 'অপেক্ষায়',
        Approval.rejected => 'বাতিল',
        Approval.suspended => 'বন্ধ',
        _ => 'সক্রিয়',
      };

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'নাম, ফোন বা ইমেইল'),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            ChoiceChip(label: const Text('সবাই'), selected: _role == null, onSelected: (_) => setState(() => _role = null)),
            for (final r in Role.label.keys)
              ChoiceChip(
                label: Text(Role.label[r]!),
                selected: _role == r,
                onSelected: (_) => setState(() => _role = r),
              ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<AppUser>>(
            stream: _users,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              final list = (snap.data ?? [])
                  .where((u) =>
                      (_role == null || u.role == _role) &&
                      (_query.isEmpty ||
                          u.name.toLowerCase().contains(_query) ||
                          u.phone.contains(_query) ||
                          u.email.toLowerCase().contains(_query)))
                  .toList();
              return ListView(padding: const EdgeInsets.all(12), children: [
                Text('${list.length} জন', style: const TextStyle(color: Colors.black54)),
                for (final u in list)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin ? JR.danger : u.isStaff ? JR.water : Colors.black26,
                        child: Icon(
                          u.role == Role.authority
                              ? Icons.account_balance
                              : u.role == Role.volunteer
                                  ? Icons.volunteer_activism
                                  : u.isAdmin
                                      ? Icons.admin_panel_settings
                                      : Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text('${u.name}${u.uid == widget.me.uid ? ' (আপনি)' : ''}'),
                      subtitle: Text([
                        '${Role.label[u.role]} • ${_statusLabel(u.status)}',
                        [u.phone, u.email].where((e) => e.isNotEmpty).join(' • '),
                        if (u.areas.isNotEmpty) 'এলাকা: ${u.areas.join(', ')}',
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: u.uid == widget.me.uid
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (a) => _menu(u, a),
                              itemBuilder: (_) => [
                                for (final r in Role.label.keys)
                                  if (r != u.role) PopupMenuItem(value: 'role:$r', child: Text('${Role.label[r]} করুন')),
                                if (u.role == Role.authority)
                                  const PopupMenuItem(value: 'areas', child: Text('এলাকা বদলান')),
                                u.status == Approval.suspended
                                    ? const PopupMenuItem(value: 'restore', child: Text('আবার চালু করুন'))
                                    : const PopupMenuItem(value: 'suspend', child: Text('সাময়িক বন্ধ করুন')),
                              ],
                            ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]);
}
