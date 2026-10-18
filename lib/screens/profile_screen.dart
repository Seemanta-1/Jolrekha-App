import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/points_service.dart';
import '../theme.dart';
import '../widgets/rewards.dart';

class ProfileScreen extends StatefulWidget {
  final AppUser me;
  const ProfileScreen({super.key, required this.me});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.me.name);
  late final _points = PointsService.mine(widget.me.uid);

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final msg = ScaffoldMessenger.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('প্রোফাইল')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'নাম',
            suffixIcon: IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                if (_name.text.trim().isEmpty) return;
                await AuthService.updateName(_name.text.trim());
                msg.showSnackBar(const SnackBar(content: Text('নাম সেভ হয়েছে')));
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined, color: JR.water),
          title: Text('ভূমিকা: ${Role.label[me.role]}'),
          subtitle: Text([
            if (me.phone.isNotEmpty) 'মোবাইল: ${me.phone}',
            if (me.email.isNotEmpty) 'ইমেইল: ${me.email}',
            if (me.org.isNotEmpty) me.org,
          ].join('\n')),
        ),
        StreamBuilder<PlayerStats>(
          stream: _points,
          builder: (context, snap) {
            final s = snap.data ?? PlayerStats(const {});
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LevelCard(stats: s),
              const SizedBox(height: 12),
              BadgeGrid(stats: s),
            ]);
          },
        ),
        if (me.isAuthority) ...[
          const Divider(height: 24),
          Text('আমার দায়িত্বের এলাকা', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(me.areas.isEmpty ? 'সব এলাকা' : me.areas.join(', ')),
          const Text('এলাকা বদলাতে অ্যাডমিনের সাথে যোগাযোগ করুন।', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
        if (me.role == Role.citizen) ...[
          const Divider(height: 24),
          const Text('স্বেচ্ছাসেবক বা ওয়ার্ড কাউন্সিল হিসেবে কাজ করতে চাইলে লগআউট করে "নতুন রেজিস্ট্রেশন" করুন।',
              style: TextStyle(color: Colors.black54)),
        ],
        const Divider(height: 32),
        OutlinedButton.icon(
          onPressed: () async {
            await LocationService.stop();
            await AuthService.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('লগআউট'),
        ),
        const SizedBox(height: 24),
        const Text(
          'জলরেখা: ঢাকার জলাবদ্ধতার পূর্বাভাস, রিপোর্ট ও সমাধান। ঝুঁকির হিসাব ২০২০–২০২৫ সালের সংবাদ থেকে তৈরি '
          'ডেটাসেট, বৃষ্টির পূর্বাভাস ও নাগরিকদের লাইভ রিপোর্টের ওপর ভিত্তি করে। AI: Google Gemini (Firebase AI Logic)।',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 4),
        const Text('AI মডেল: ${AppConfig.aiModel}', style: TextStyle(fontSize: 11, color: Colors.black38)),
      ]),
    );
  }
}
