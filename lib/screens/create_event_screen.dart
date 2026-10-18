import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';

/// A volunteer picks the place on the map and the time; everyone nearby is invited.
class CreateEventScreen extends StatefulWidget {
  final AppUser me;
  final LatLng? at;
  final DateTime? startAt;
  final String? title, description;
  final bool aiSuggested;

  const CreateEventScreen({
    super.key,
    required this.me,
    this.at,
    this.startAt,
    this.title,
    this.description,
    this.aiSuggested = false,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final _title = TextEditingController(text: widget.title ?? 'ড্রেনের মুখ পরিষ্কার অভিযান');
  late final _desc = TextEditingController(
      text: widget.description ?? 'গ্লাভস ও বস্তা আনুন। ড্রেনের মুখ থেকে প্লাস্টিক ও ময়লা তুলব, যাতে বৃষ্টিতে পানি না জমে।');
  late LatLng? _at = widget.at;
  late DateTime _start = widget.startAt ?? DateTime.now().add(const Duration(hours: 3));
  bool _busy = false;

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() => _start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_at == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ম্যাপে ট্যাপ করে জায়গা বাছুন')));
      return;
    }
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      await EventService.create(
        me: widget.me,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        at: _at!,
        startAt: _start,
        aiSuggested: widget.aiSuggested,
      );
      nav.pop();
      msg.showSnackBar(SnackBar(
          content: Text('অভিযান তৈরি হয়েছে। ${AppConfig.eventNotifyRadiusKm.toStringAsFixed(0)} কিমির মধ্যে '
              'সবার কাছে আমন্ত্রণ যাবে।')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('হয়নি: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _at ?? LocationService.position.value ?? const LatLng(AppConfig.dhakaLat, AppConfig.dhakaLon);
    return Scaffold(
      appBar: AppBar(
        title: const Text('নতুন পরিষ্কার অভিযান'),
        actions: [
          if (widget.aiSuggested) const Padding(padding: EdgeInsets.only(right: 12), child: AiBadge(label: 'AI পরামর্শ')),
        ],
      ),
      body: ListView(children: [
        SizedBox(
          height: 260,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
              onTap: (_, p) => setState(() => _at = p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.jolrekha.app',
              ),
              if (_at != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _at!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: JR.done, size: 40),
                  ),
                ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _at == null
                  ? 'ম্যাপে ট্যাপ করে অভিযানের জায়গা বাছুন'
                  : 'জায়গা: ${_at!.latitude.toStringAsFixed(4)}, ${_at!.longitude.toStringAsFixed(4)} (বদলাতে ম্যাপে ট্যাপ করুন)',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'শিরোনাম')),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'বিবরণ (কী আনতে হবে, কোথায় দেখা হবে)'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(whenBn(_start)),
              trailing: TextButton(onPressed: _pickTime, child: const Text('সময় বদলান')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.campaign),
              label: const Text('অভিযান ঘোষণা করুন'),
            ),
          ]),
        ),
      ]),
    );
  }
}
