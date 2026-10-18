import 'package:flutter/material.dart';

/// Marks every place where AI is at work, so users (and judges) can see it.
class AiBadge extends StatelessWidget {
  final String label;
  final bool small;
  const AiBadge({super.key, this.label = 'AI', this.small = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6A3DE8), Color(0xFF1F6F9F)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: small ? 11 : 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(color: Colors.white, fontSize: small ? 10 : 11, fontWeight: FontWeight.w700)),
        ]),
      );
}
