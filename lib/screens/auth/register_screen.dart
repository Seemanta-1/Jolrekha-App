import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/risk_service.dart';

/// Registration for volunteers and ward councils: verified email + admin approval.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _org = TextEditingController();
  String _role = Role.volunteer;
  final _areas = <String>{};
  List<String> _allAreas = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RiskService.places().then((p) {
      if (mounted) setState(() => _allAreas = p.map((e) => e.area).toList()..sort());
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_role == Role.authority && _areas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দায়িত্বের অন্তত একটি এলাকা বাছুন')));
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      await AuthService.registerStaff(
        role: _role,
        name: _name.text.trim(),
        phone: AuthService.normalizePhone(_phone.text)!,
        email: _email.text.trim(),
        password: _password.text,
        org: _org.text.trim(),
        areas: _role == Role.authority ? (_areas.toList()..sort()) : [],
      );
      nav.popUntil((r) => r.isFirst); // the auth gate now shows "verify your email"
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(authErrorBn(e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final council = _role == Role.authority;
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন রেজিস্ট্রেশন')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: Role.volunteer, label: Text('স্বেচ্ছাসেবক'), icon: Icon(Icons.volunteer_activism)),
                  ButtonSegment(value: Role.authority, label: Text('ওয়ার্ড কাউন্সিল'), icon: Icon(Icons.account_balance)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'পূর্ণ নাম'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'নাম দিন' : null,
              ),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'মোবাইল নম্বর', hintText: '01XXXXXXXXX'),
                validator: (v) => AuthService.normalizePhone(v ?? '') == null ? 'সঠিক মোবাইল নম্বর দিন' : null,
              ),
              TextFormField(
                controller: _org,
                decoration: InputDecoration(
                    labelText: council ? 'পদবি ও ওয়ার্ড নম্বর' : 'সংগঠন / টিমের নাম (ঐচ্ছিক)',
                    hintText: council ? 'যেমন: কাউন্সিলর, ওয়ার্ড ১৯' : null),
                validator: (v) => council && (v ?? '').trim().isEmpty ? 'পদবি ও ওয়ার্ড দিন' : null,
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'ইমেইল'),
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'সঠিক ইমেইল দিন',
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)'),
                validator: (v) => (v ?? '').length < 6 ? 'কমপক্ষে ৬ অক্ষর' : null,
              ),
              if (council) ...[
                const SizedBox(height: 16),
                Text('দায়িত্বের এলাকা', style: Theme.of(context).textTheme.titleMedium),
                const Text('এই এলাকাগুলোর রিপোর্ট আপনার ড্যাশবোর্ডে আসবে।', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final a in _allAreas)
                    FilterChip(
                      label: Text(a),
                      selected: _areas.contains(a),
                      onSelected: (v) => setState(() => v ? _areas.add(a) : _areas.remove(a)),
                    ),
                ]),
              ],
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('রেজিস্ট্রেশন করুন'),
              ),
              const SizedBox(height: 10),
              const Text(
                'রেজিস্ট্রেশনের পর ইমেইলে একটি যাচাই লিংক যাবে। ইমেইল যাচাই ও অ্যাডমিনের অনুমোদনের পর আপনার ড্যাশবোর্ড খুলবে।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
