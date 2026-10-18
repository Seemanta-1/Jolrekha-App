import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/risk_service.dart';

/// Ward contacts used by "forward to the ward council" (WhatsApp / email) in the app:
/// `contacts/{area}` = {name, phone, email}.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  static final _contacts = FirebaseFirestore.instance.collection('contacts');
  final _all = _contacts.snapshots();
  List<String> _areas = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    RiskService.places().then((p) {
      if (mounted) setState(() => _areas = p.map((e) => e.area).toList()..sort());
    });
  }

  Future<void> _edit(String area, Map<String, dynamic>? c) async {
    final name = TextEditingController(text: c?['name'] as String? ?? '');
    final phone = TextEditingController(text: c?['phone'] as String? ?? '');
    final email = TextEditingController(text: c?['email'] as String? ?? '');
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$area: ওয়ার্ড যোগাযোগ'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'নাম ও পদবি')),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp নম্বর', hintText: '8801XXXXXXXXX'),
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'ইমেইল'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('সেভ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _contacts.doc(area).set({
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      msg.showSnackBar(SnackBar(content: Text('$area সেভ হয়েছে')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('হয়নি: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'এলাকা খুঁজুন'),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('অ্যাপে "WhatsApp / ইমেইল" চাপলে বার্তা এই নম্বর ও ইমেইলে যায়।',
                  style: TextStyle(color: Colors.black54)),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _all,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              final byArea = {for (final d in snap.data?.docs ?? []) d.id: d.data()};
              final areas = _areas.where((a) => _query.isEmpty || a.toLowerCase().contains(_query)).toList()
                ..sort((a, b) => (byArea[a] == null ? 1 : 0).compareTo(byArea[b] == null ? 1 : 0));
              return ListView(padding: const EdgeInsets.all(12), children: [
                Text('${byArea.length}/${_areas.length} এলাকার যোগাযোগ দেওয়া আছে',
                    style: const TextStyle(color: Colors.black54)),
                for (final a in areas)
                  Card(
                    child: ListTile(
                      leading: Icon(byArea[a] == null ? Icons.help_outline : Icons.check_circle,
                          color: byArea[a] == null ? Colors.black38 : Colors.green),
                      title: Text(a),
                      subtitle: Text(byArea[a] == null
                          ? 'যোগাযোগ দেওয়া নেই'
                          : [byArea[a]!['name'], byArea[a]!['phone'], byArea[a]!['email']]
                              .where((e) => (e as String? ?? '').isNotEmpty)
                              .join(' • ')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _edit(a, byArea[a]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]);
}
