import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'admin_home.dart';

/// Admin website: same Firebase project as the app, so an approval here opens
/// the user's dashboard in the app at once.
/// Build: flutter build web -t lib/admin/admin_main.dart -o build/admin
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'জলরেখা অ্যাডমিন',
        debugShowCheckedModeBanner: false,
        theme: JR.theme(),
        home: const _AdminGate(),
      );
}

class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: AuthService.authChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snap.data;
          if (user == null) return const _AdminLogin();
          return StreamBuilder<AppUser?>(
            key: ValueKey(user.uid),
            stream: AuthService.watchUser(user.uid),
            builder: (context, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final me = s.data;
              if (me == null || !me.isAdmin) return _NotAdmin(email: user.email ?? '');
              return AdminHome(me: me);
            },
          );
        },
      );
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin();

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      await AuthService.staffLogin(email: _email.text, password: _password.text);
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(authErrorBn(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final msg = ScaffoldMessenger.of(context);
    if (_email.text.trim().isEmpty) {
      msg.showSnackBar(const SnackBar(content: Text('আগে ইমেইল লিখুন')));
      return;
    }
    try {
      await AuthService.resetPassword(_email.text);
      msg.showSnackBar(const SnackBar(content: Text('পাসওয়ার্ড বদলানোর লিংক ইমেইলে পাঠানো হয়েছে')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(authErrorBn(e))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.admin_panel_settings, size: 48, color: JR.water),
                  const SizedBox(height: 8),
                  Text('জলরেখা অ্যাডমিন',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'ইমেইল', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'পাসওয়ার্ড', prefixIcon: Icon(Icons.lock_outline)),
                    onSubmitted: (_) => _login(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _forgot, child: const Text('পাসওয়ার্ড ভুলে গেছেন?')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : _login,
                    child: const Text('লগইন'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _NotAdmin extends StatelessWidget {
  final String email;
  const _NotAdmin({required this.email});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock, size: 48, color: JR.high),
            const SizedBox(height: 12),
            Text('$email অ্যাডমিন অ্যাকাউন্ট নয়', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Firebase console এ users ডকুমেন্টে role: admin দিলে এখানে ঢুকতে পারবেন।',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            const OutlinedButton(onPressed: AuthService.signOut, child: Text('লগআউট')),
          ]),
        ),
      );
}
