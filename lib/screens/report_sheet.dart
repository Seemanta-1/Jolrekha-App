import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/incident.dart';
import '../services/ai_service.dart';
import '../services/incident_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';

/// Report: snap a photo and let the AI fill the form, or pick the problem by hand. Location comes from GPS or the map.
class ReportSheet extends StatefulWidget {
  final LatLng at;
  const ReportSheet({super.key, required this.at});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  IncidentType _type = IncidentType.water;
  String _depth = 'knee';
  final _note = TextEditingController();
  bool _sending = false;

  // AI photo check
  String? _photo; // base64 thumbnail
  PhotoAnalysis? _ai;
  String? _aiError; // shown inside the sheet (a snackbar would hide behind it)
  bool _analyzing = false;

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 640, maxHeight: 640, imageQuality: 55);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _analyzing = true;
      _ai = null;
      _aiError = null;
      _photo = bytes.length < 350 * 1024 ? base64Encode(bytes) : null; // keep Firestore docs small
    });
    try {
      final a = await AiService.analyzePhoto(bytes, x.mimeType ?? 'image/jpeg');
      if (!mounted) return;
      setState(() {
        _ai = a;
        if (a.relevant) {
          _type = a.type;
          if (a.type == IncidentType.water && a.depth != 'none') _depth = a.depth;
          if (a.type == IncidentType.other) _note.text = a.summary;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _aiError = aiErrorBn(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _send() async {
    if (_type == IncidentType.other && _note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সমস্যাটি সংক্ষেপে লিখুন')));
      return;
    }
    setState(() => _sending = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    // the AI only counts if the user kept the problem it found
    final ai = _ai != null && _ai!.type == _type ? _ai : null;
    try {
      await IncidentService.submitReport(
        type: _type,
        depth: _depth,
        at: widget.at,
        note: _type == IncidentType.other ? _note.text.trim() : null,
        photo: _ai?.relevant == true ? _photo : null,
        ai: ai,
      );
      nav.pop();
      msg.showSnackBar(SnackBar(
        content: Text(dangerTypes.contains(_type)
            ? 'জরুরি রিপোর্ট পাঠানো হয়েছে। ওয়ার্ড কাউন্সিল ও কাছের সবাইকে সতর্ক করা হচ্ছে।'
            : ai != null && ai.trusted
                ? 'AI ছবি যাচাই করেছে, রিপোর্ট দ্রুত যাচাইকৃত হবে। +১০ পয়েন্ট'
                : 'রিপোর্ট পাঠানো হয়েছে। আশেপাশের মানুষ নিশ্চিত করলে যাচাইকৃত হবে। +৫ পয়েন্ট'),
      ));
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      msg.showSnackBar(SnackBar(content: Text('পাঠানো যায়নি: $e')));
    }
  }

  Widget _aiCard() {
    if (_analyzing) {
      return const Card(
        child: ListTile(
          leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('AI ছবি দেখছে… (প্রায় ৫ সেকেন্ড)'),
          trailing: AiBadge(small: true),
        ),
      );
    }
    if (_aiError != null) {
      return Card(
        color: JR.high.withValues(alpha: 0.08),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: JR.high),
          title: Text(_aiError!),
          subtitle: const Text('নিচ থেকে হাতে বেছে রিপোর্ট পাঠাতে পারেন।'),
          trailing: const AiBadge(small: true),
        ),
      );
    }
    final a = _ai;
    if (a == null) return const SizedBox.shrink();
    final color = a.relevant ? JR.done : JR.high;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(base64Decode(_photo!), width: 64, height: 64, fit: BoxFit.cover),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const AiBadge(label: 'AI যাচাই', small: true),
                const SizedBox(width: 6),
                Text('${(a.confidence * 100).round()}% নিশ্চিত', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              if (a.relevant) ...[
                Text('${typeLabel[a.type]}${a.depth != 'none' ? ', ${depthLabel[a.depth]} পানি' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (a.plastic) const Text('ড্রেন/পানিতে প্লাস্টিক দেখা যাচ্ছে', style: TextStyle(color: JR.high)),
              ] else
                const Text('ছবিতে কোনো রাস্তার সমস্যা দেখা যাচ্ছে না। ঠিক ছবি দিন বা হাতে বাছুন।',
                    style: TextStyle(color: JR.high)),
              if (a.summary.isNotEmpty) Text(a.summary, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget typeTile(IncidentType t) {
      final c = dangerTypes.contains(t) ? JR.danger : JR.water;
      final on = _type == t;
      return SizedBox(
        width: 84,
        child: InkWell(
          onTap: () => setState(() => _type = t),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? c : Colors.black12, width: on ? 2.5 : 1),
              color: on ? c.withValues(alpha: 0.08) : null,
            ),
            child: Column(children: [
              Icon(typeIcon[t], color: c, size: 26),
              const SizedBox(height: 4),
              Text(typeLabel[t]!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('কী দেখছেন?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        // AI #1: photo report
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _analyzing ? null : () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('ছবি তুলুন'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _analyzing ? null : () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('গ্যালারি'),
            ),
          ),
          const SizedBox(width: 8),
          const AiBadge(small: true),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 6),
          child: Text('ছবি দিলে AI নিজেই সমস্যা, পানির গভীরতা ও প্লাস্টিক চিনে ফর্ম পূরণ করবে।',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        _aiCard(),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final t in IncidentType.values) typeTile(t)]),
        if (_type == IncidentType.water) ...[
          const SizedBox(height: 14),
          Text('পানি কতটা?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ankle', label: Text('গোড়ালি')),
              ButtonSegment(value: 'knee', label: Text('হাঁটু')),
              ButtonSegment(value: 'waist', label: Text('কোমর')),
              ButtonSegment(value: 'chest', label: Text('বুক+')),
            ],
            selected: {_depth},
            onSelectionChanged: (s) => setState(() => _depth = s.first),
          ),
        ],
        if (_type == IncidentType.other) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'সমস্যাটি সংক্ষেপে লিখুন'),
          ),
        ],
        if (dangerTypes.contains(_type)) ...[
          const SizedBox(height: 12),
          const Text('নিজে কাছে যাবেন না। রিপোর্টটি সরাসরি ওয়ার্ড কাউন্সিলের কাছে জরুরি হিসেবে যাবে।',
              style: TextStyle(color: JR.danger)),
        ],
        const SizedBox(height: 8),
        Text(
          'অবস্থান: ${widget.at.latitude.toStringAsFixed(4)}, ${widget.at.longitude.toStringAsFixed(4)} '
          '(অন্য জায়গার জন্য ম্যাপে চেপে ধরুন)',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: dangerTypes.contains(_type) ? JR.danger : JR.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_analyzing ? 'AI ছাড়াই এখনই পাঠান' : 'রিপোর্ট পাঠান'),
          ),
        ),
      ]),
    );
  }
}
