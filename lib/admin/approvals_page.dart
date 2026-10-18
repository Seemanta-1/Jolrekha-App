import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

/// Approve or reject volunteer and ward council registrations. An approval opens the user's
/// dashboard in the app at once (same Firestore document).
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final _pending = AuthService.watchPending();

  Future<void> _act(Future<void> Function() f, String done) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await f();
      msg.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('হয়নি: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppUser>>(
        stream: _pending,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('অনুমোদনের অপেক্ষায় কেউ নেই', style: TextStyle(color: Colors.black54)));
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final u in list)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(u.requestedRole == Role.authority ? Icons.account_balance : Icons.volunteer_activism,
                          color: JR.water),
                      const SizedBox(width: 8),
                      Expanded(child: Text(u.name, style: Theme.of(context).textTheme.titleMedium)),
                      Chip(label: Text(Role.label[u.requestedRole] ?? '')),
                    ]),
                    Text('${u.email} • ${u.phone}'),
                    if (u.org.isNotEmpty) Text(u.org, style: const TextStyle(color: Colors.black54)),
                    if (u.areas.isNotEmpty)
                      Text('এলাকা: ${u.areas.join(', ')}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(u.emailVerified ? '✓ ইমেইল যাচাই হয়েছে' : '✗ ইমেইল এখনো যাচাই হয়নি',
                        style: TextStyle(color: u.emailVerified ? JR.done : JR.high, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(children: [
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: JR.done),
                        onPressed: () => _act(() => AuthService.approve(u), '${u.name} অনুমোদিত'),
                        child: const Text('অনুমোদন'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _act(() => AuthService.reject(u), '${u.name} বাতিল'),
                        child: const Text('বাতিল'),
                      ),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      );
}
