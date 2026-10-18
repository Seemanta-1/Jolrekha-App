import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme.dart';
import '../home_shell.dart';
import 'login_screen.dart';

/// Signed out → login. Volunteer / council registrations → verify email → wait for admin approval.
/// Everyone else → their dashboard.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: AuthService.authChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const _Loading();
          final user = snap.data;
          if (user == null) return const LoginScreen();
          return _UserGate(key: ValueKey(user.uid), uid: user.uid);
        },
      );
}

class _UserGate extends StatefulWidget {
  final String uid;
  const _UserGate({super.key, required this.uid});

  @override
  State<_UserGate> createState() => _UserGateState();
}

class _UserGateState extends State<_UserGate> {
  late final _me = AuthService.watchUser(widget.uid);

  @override
  Widget build(BuildContext context) => StreamBuilder<AppUser?>(
        stream: _me,
        builder: (context, snap) {
          final me = snap.data;
          if (me == null) return const _Loading(showSignOut: true);
          if (me.status == Approval.suspended) {
            return const _Message(
              icon: Icons.pause_circle_outline,
              title: 'অ্যাকাউন্ট সাময়িক বন্ধ',
              text: 'আরও তথ্যের জন্য জলরেখা অ্যাডমিনের সাথে যোগাযোগ করুন।',
            );
          }
          if (me.status == Approval.rejected) {
            return const _Message(
              icon: Icons.block,
              title: 'রেজিস্ট্রেশন অনুমোদন হয়নি',
              text: 'আরও তথ্যের জন্য জলরেখা অ্যাডমিনের সাথে যোগাযোগ করুন।',
            );
          }
          if (me.isPending) {
            final verified = me.emailVerified || (AuthService.current?.emailVerified ?? false);
            if (!verified) return _VerifyEmail(email: me.email);
            return _Message(
              icon: Icons.hourglass_top,
              title: 'অনুমোদনের অপেক্ষায়',
              text: 'আপনার ইমেইল যাচাই হয়েছে। অ্যাডমিন অনুমোদন দিলেই ${Role.label[me.requestedRole] ?? ''} '
                  'ড্যাশবোর্ড এখানে নিজে থেকেই খুলে যাবে।',
            );
          }
          return HomeShell(me: me);
        },
      );
}

class _VerifyEmail extends StatefulWidget {
  final String email;
  const _VerifyEmail({required this.email});

  @override
  State<_VerifyEmail> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends State<_VerifyEmail> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      if (!await AuthService.checkEmailVerified()) {
        msg.showSnackBar(const SnackBar(content: Text('এখনো যাচাই হয়নি। ইমেইলের লিংকে ক্লিক করুন।')));
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(authErrorBn(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await AuthService.resendVerification();
      msg.showSnackBar(const SnackBar(content: Text('আবার পাঠানো হয়েছে')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text(authErrorBn(e))));
    }
  }

  @override
  Widget build(BuildContext context) => _Message(
        icon: Icons.mark_email_unread_outlined,
        title: 'ইমেইল যাচাই করুন',
        text: '${widget.email} ঠিকানায় একটি যাচাই লিংক পাঠানো হয়েছে (স্প্যাম ফোল্ডারও দেখুন)। '
            'লিংকে ক্লিক করে নিচের বোতাম চাপুন।',
        actions: [
          FilledButton(
            onPressed: _busy ? null : _check,
            child: const Text('যাচাই করেছি'),
          ),
          TextButton(onPressed: _resend, child: const Text('আবার পাঠান')),
        ],
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final List<Widget> actions;
  const _Message({required this.icon, required this.title, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 56, color: JR.water),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 20),
                ...actions,
                const TextButton(onPressed: AuthService.signOut, child: Text('লগআউট')),
              ]),
            ),
          ),
        ),
      );
}

class _Loading extends StatelessWidget {
  final bool showSignOut;
  const _Loading({this.showSignOut = false});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (showSignOut) ...[
              const SizedBox(height: 24),
              const TextButton(onPressed: AuthService.signOut, child: Text('লগআউট')),
            ],
          ]),
        ),
      );
}
