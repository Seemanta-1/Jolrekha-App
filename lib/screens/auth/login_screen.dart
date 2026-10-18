import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme.dart';
import 'register_screen.dart';

/// Citizens: name + phone number, no OTP. Volunteers and ward councils: email + password.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const SizedBox(height: 24),
                const Icon(Icons.water_drop, size: 56, color: JR.water),
                const SizedBox(height: 8),
                Text('জলরেখা',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: JR.ink)),
                const Text('ঢাকার জলাবদ্ধতার পূর্বাভাস, রিপোর্ট ও সমাধান',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
                const TabBar(tabs: [
                  Tab(text: 'নাগরিক'),
                  Tab(text: 'স্বেচ্ছাসেবক / কাউন্সিল'),
                ]),
                const SizedBox(height: 16),
                const SizedBox(
                  height: 400,
                  child: TabBarView(children: [_CitizenLogin(), _StaffLogin()]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class _CitizenLogin extends StatefulWidget {
  const _CitizenLogin();

  @override
  State<_CitizenLogin> createState() => _CitizenLoginState();
}

class _CitizenLoginState extends State<_CitizenLogin> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  Future<void> _go() async {
    final phone = AuthService.normalizePhone(_phone.text);
    if (phone == null) return _snack(context, 'সঠিক মোবাইল নম্বর দিন (01XXXXXXXXX)');
    setState(() => _busy = true);
    try {
      await AuthService.phoneLogin(name: _name.text.trim().isEmpty ? 'নাগরিক' : _name.text.trim(), phone: phone);
    } catch (e) {
      if (mounted) _snack(context, authErrorBn(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'আপনার নাম', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
              labelText: 'মোবাইল নম্বর', hintText: '01XXXXXXXXX', prefixIcon: Icon(Icons.phone_outlined)),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy ? null : _go,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('প্রবেশ করুন'),
        ),
        const SizedBox(height: 10),
        const Text('কোনো OTP লাগবে না। একই নম্বর দিলে যেকোনো ফোনে আপনার পয়েন্ট ফিরে পাবেন।',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}

class _StaffLogin extends StatefulWidget {
  const _StaffLogin();

  @override
  State<_StaffLogin> createState() => _StaffLoginState();
}

class _StaffLoginState extends State<_StaffLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _hide = true;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await AuthService.staffLogin(email: _email.text, password: _password.text);
    } catch (e) {
      if (mounted) _snack(context, authErrorBn(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('পাসওয়ার্ড ভুলে গেছেন?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('আপনার ইমেইলে পাসওয়ার্ড বদলানোর লিংক পাঠানো হবে।'),
          TextField(controller: c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'ইমেইল')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('লিংক পাঠান')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await AuthService.resetPassword(email);
      if (mounted) _snack(context, 'লিংক পাঠানো হয়েছে। ইমেইল (স্প্যাম ফোল্ডারসহ) দেখুন।');
    } catch (e) {
      if (mounted) _snack(context, authErrorBn(e));
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'ইমেইল', prefixIcon: Icon(Icons.email_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          decoration: InputDecoration(
            labelText: 'পাসওয়ার্ড',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          onSubmitted: (_) => _login(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _forgot, child: const Text('পাসওয়ার্ড ভুলে গেছেন?')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('লগইন'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
          icon: const Icon(Icons.how_to_reg_outlined),
          label: const Text('নতুন রেজিস্ট্রেশন'),
        ),
      ]);
}
