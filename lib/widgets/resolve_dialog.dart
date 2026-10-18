import 'package:flutter/material.dart';

import '../models/incident.dart';

class ResolveResult {
  final String cause;
  final double plasticKg;
  final int inlets;
  final String note;
  ResolveResult(this.cause, this.plasticKg, this.inlets, this.note);
}

/// Asked when a volunteer or authority marks something resolved.
/// Records why the water collected and what was cleaned: this is the environmental data.
Future<ResolveResult?> showResolveDialog(BuildContext context, {bool askCause = true}) {
  String cause = 'plastic';
  final kg = TextEditingController(text: '0');
  final inlets = TextEditingController(text: '1');
  final note = TextEditingController();
  return showDialog<ResolveResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('কাজ শেষ হয়েছে'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (askCause) ...[
              const Text('পানি জমার কারণ'),
              DropdownButton<String>(
                isExpanded: true,
                value: cause,
                items: [
                  for (final e in causeLabel.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setS(() => cause = v ?? cause),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: kg,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'তোলা প্লাস্টিক/বর্জ্য (কেজি, আনুমানিক)'),
            ),
            TextField(
              controller: inlets,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'পরিষ্কার করা ড্রেনের মুখ (সংখ্যা)'),
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'মন্তব্য (ঐচ্ছিক)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              ResolveResult(
                cause,
                double.tryParse(kg.text.trim()) ?? 0,
                int.tryParse(inlets.text.trim()) ?? 0,
                note.text.trim(),
              ),
            ),
            child: const Text('সমাধান হয়েছে'),
          ),
        ],
      ),
    ),
  );
}
