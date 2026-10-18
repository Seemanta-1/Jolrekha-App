import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/incident.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/incident_service.dart';
import '../services/location_service.dart';
import '../services/risk_service.dart';
import '../services/route_service.dart';
import '../theme.dart';
import '../widgets/ai_badge.dart';
import 'event_chat_screen.dart';
import 'incident_sheet.dart';
import 'report_sheet.dart';

class MapScreen extends StatefulWidget {
  final AppUser me;
  const MapScreen({super.key, required this.me});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  List<DayRisk> _days = [];
  double _worstP = 0;
  List<PlaceRisk> _risks = [];
  String? _riskError;
  List<Incident> _incidents = [];
  List<CleanupEvent> _events = [];
  bool _routeMode = false;
  bool _showRisk = true;
  bool _showLegend = true;
  bool _depthMode = false; // colour water by depth: what can get through
  Vehicle _vehicle = Vehicle.car;
  RouteResult? _route;
  bool _routing = false;
  final _alerted = <String>{};
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _loadForecast();
    _subs.add(IncidentService.watchOpen().listen((list) {
      setState(() => _incidents = list);
      _updateRisk();
      _checkDanger();
    }));
    _subs.add(EventService.watchActive().listen((e) => setState(() => _events = e)));
    LocationService.position.addListener(_onMove);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    LocationService.position.removeListener(_onMove);
    super.dispose();
  }

  void _onMove() {
    if (!mounted) return;
    setState(() {});
    _checkDanger();
  }

  Future<void> _loadForecast() async {
    try {
      final days = await RiskService.forecast();
      if (!mounted) return;
      setState(() {
        _days = days;
        _worstP = days.map((d) => d.pCity).reduce(max);
        _riskError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _riskError = 'পূর্বাভাস পাওয়া যায়নি, ইন্টারনেট দেখুন');
    }
    await _updateRisk();
  }

  /// AI #2: forecast model + live crowd reports.
  Future<void> _updateRisk() async {
    final risks = await RiskService.placeRisks(_worstP, crowd: _incidents);
    if (mounted) setState(() => _risks = risks);
  }

  /// Safety alert: live wire or open manhole within 200 m.
  void _checkDanger() {
    final me = LocationService.position.value;
    if (me == null || !mounted) return;
    const d = Distance();
    for (final i in _incidents) {
      if (!i.isDanger || i.status == Status.resolved || _alerted.contains(i.id)) continue;
      final m = d.as(LengthUnit.Meter, me, i.point);
      if (m <= AppConfig.dangerAlertRadiusM) {
        _alerted.add(i.id);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(typeIcon[i.type], color: JR.danger, size: 40),
            title: Text('সামনে ${typeLabel[i.type]}'),
            content: Text('প্রায় ${m.round()} মিটার দূরে (${i.area})। ওদিকে যাবেন না, অন্য পথ ব্যবহার করুন।'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বুঝেছি'))],
          ),
        );
        break;
      }
    }
  }

  LatLng get _center => LocationService.position.value ?? _map.camera.center;

  void _openReport(LatLng at) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ReportSheet(at: at),
      );

  Future<void> _routeTo(LatLng dest) async {
    if (AppConfig.orsApiKey.isEmpty) {
      _snack('রুটের জন্য env.json এ OpenRouteService key দিন');
      return;
    }
    setState(() => _routing = true);
    final avoid = <LatLng>[
      for (final i in _incidents)
        if (i.status != Status.resolved && i.type != IncidentType.streetlight && !i.passableBy(_vehicle)) i.point,
      for (final r in _risks)
        if (r.level == 'high') r.place.point,
    ];
    try {
      final r = await RouteService.route(_center, dest, avoid, profile: vehicleProfile[_vehicle]!);
      if (mounted) setState(() => _route = r);
    } catch (e) {
      _snack('রুট পাওয়া যায়নি: $e');
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ---------- layers ----------

  List<CircleMarker> _hotspotCircles() => [
        for (final r in _risks.reversed.where((r) => r.level != 'low')) // high risk drawn last, on top
          CircleMarker(
            point: r.place.point,
            radius: 260,
            useRadiusInMeter: true,
            color: JR.risk(r.level).withValues(alpha: 0.20),
            borderColor: JR.risk(r.level),
            borderStrokeWidth: r.level == 'high' ? 3 : 2,
          ),
      ];

  /// Heat colouring: the more people mark a spot, the bigger and redder its halo.
  List<CircleMarker> _heatCircles() => [
        for (final i in _incidents.where((i) => i.status != Status.resolved).toList()
          ..sort((a, b) => a.weight.compareTo(b.weight)))
          CircleMarker(
            point: i.point,
            radius: 50.0 + 30 * min(i.weight, 6),
            useRadiusInMeter: true,
            color: _heat(i.weight).withValues(alpha: 0.45),
            borderColor: _heat(i.weight),
            borderStrokeWidth: 2,
          ),
      ];

  /// Depth colouring: water spots by what can get through; faint where the chosen vehicle passes.
  List<CircleMarker> _depthCircles() => [
        for (final i in _incidents.where((i) => i.status != Status.resolved && i.type == IncidentType.water).toList()
          ..sort((a, b) => (depthRank[a.depth] ?? 0).compareTo(depthRank[b.depth] ?? 0)))
          CircleMarker(
            point: i.point,
            radius: 80.0 + 40 * (depthRank[i.depth] ?? 0),
            useRadiusInMeter: true,
            color: JR.depth(i.depth).withValues(alpha: i.passableBy(_vehicle) ? 0.15 : 0.5),
            borderColor: JR.depth(i.depth),
            borderStrokeWidth: i.passableBy(_vehicle) ? 1 : 3,
          ),
      ];

  int get _blockedForVehicle => _incidents
      .where((i) => i.status != Status.resolved && i.type == IncidentType.water && !i.passableBy(_vehicle))
      .length;

  static Color _heat(int w) => w >= 4
      ? JR.heat3
      : w >= 2
          ? JR.heat2
          : JR.heat1;

  Widget _incidentIcon(Incident i) {
    final color = i.isDanger
        ? JR.danger
        : i.status == Status.resolved
            ? JR.done
            : JR.water;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => IncidentSheet(incident: i, me: widget.me),
      ),
      child: Opacity(
        opacity: i.isVerified ? 1 : 0.7,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: i.isVerified ? 3 : 1.5),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(typeIcon[i.type], color: color, size: 20),
            if (i.weight > 1)
              Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(
                  radius: 7,
                  backgroundColor: _heat(i.weight),
                  child: Text('${i.weight}', style: const TextStyle(fontSize: 8, color: Colors.white)),
                ),
              ),
            if (i.aiBoost > 0)
              const Positioned(left: 0, bottom: 0, child: Icon(Icons.auto_awesome, size: 11, color: Color(0xFF6A3DE8))),
          ]),
        ),
      ),
    );
  }

  Widget _eventIcon(CleanupEvent e) => GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.title, style: Theme.of(ctx).textTheme.titleLarge)),
                  if (e.aiSuggested) const AiBadge(label: 'AI পরিকল্পনা', small: true),
                ]),
                Text('${e.area} • ${whenBn(e.startAt)} • ${e.members.length} জন'),
                if (e.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e.description)),
                const SizedBox(height: 12),
                e.isMember(widget.me.uid)
                    ? FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => EventChatScreen(event: e, me: widget.me)));
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('টিম চ্যাট'),
                      )
                    : FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await EventService.join(e);
                          _snack('টিমে যোগ দিয়েছেন! +১০ পয়েন্ট');
                        },
                        icon: const Icon(Icons.group_add),
                        label: const Text('যোগ দিন'),
                      ),
              ]),
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(color: JR.done, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: const Icon(Icons.cleaning_services, color: Colors.white, size: 18),
        ),
      );

  // ---------- UI ----------

  Widget _banner() {
    if (_days.isEmpty) {
      return _card(Text(_riskError ?? 'পূর্বাভাস লোড হচ্ছে…', style: const TextStyle(color: JR.ink)));
    }
    final maxP = _risks.isEmpty ? 0.0 : _risks.map((r) => r.risk).reduce(max);
    Widget day(String label, DayRisk d) {
      final top = _worstP == 0 ? 0.0 : maxP * d.pCity / _worstP;
      final lv = RiskService.levelOf(top);
      return Expanded(
        child: Row(children: [
          Container(width: 6, height: 38, color: JR.risk(lv)),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: JR.ink)),
            Text('${d.rainMm.toStringAsFixed(0)} মিমি বৃষ্টি',
                style: const TextStyle(fontWeight: FontWeight.w700, color: JR.ink)),
            Text('ঝুঁকি ${JR.levelLabel[lv]}', style: TextStyle(fontSize: 12, color: JR.risk(lv))),
          ]),
        ]),
      );
    }

    final hot = _risks.where((r) => r.level == 'high').map((r) => r.place.area).take(3).toList();
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        day('আজ', _days.first),
        if (_days.length > 1) day('আগামীকাল', _days[1]),
        const AiBadge(label: 'AI ঝুঁকি', small: true),
      ]),
      if (hot.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('উচ্চ ঝুঁকি: ${hot.join(', ')}', style: const TextStyle(fontSize: 12, color: JR.riskHigh)),
        ),
    ]));
  }

  /// What the colours and symbols on the map mean.
  Widget _legend() {
    Widget dot(Color c, {bool ring = false}) => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring ? c.withValues(alpha: 0.20) : c.withValues(alpha: 0.75),
            border: Border.all(color: c, width: ring ? 2.5 : 1.5),
          ),
        );
    Widget item(Widget sym, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          sym,
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 11))),
        ]);
    Widget title(String t, {bool ai = false}) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: JR.ink)),
            if (ai) ...[const SizedBox(width: 4), const AiBadge(small: true)],
          ]),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Card(
        elevation: 3,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('ম্যাপের রং', style: TextStyle(fontWeight: FontWeight.w800, color: JR.ink))),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => setState(() => _showLegend = false),
                icon: const Icon(Icons.close),
              ),
            ]),
            if (_depthMode) ...[
              title('পানির গভীরতা (কী চলবে)'),
              Wrap(spacing: 10, runSpacing: 4, children: [
                for (final d in passLabel.keys) item(dot(JR.depth(d)), '${depthLabel[d]}: ${passLabel[d]}'),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('হালকা = ${vehicleLabel[_vehicle]} যেতে পারবে, গাঢ় = পারবে না',
                    style: const TextStyle(fontSize: 10, color: Colors.black54)),
              ),
            ] else ...[
              title('মানুষের রিপোর্ট (কতজন জানিয়েছেন)'),
              Wrap(spacing: 10, runSpacing: 4, children: [
                item(dot(JR.heat1), '১ জন'),
                item(dot(JR.heat2), '২–৩ জন'),
                item(dot(JR.heat3), '৪+ জন'),
              ]),
            ],
            title('পানি জমার ঝুঁকি', ai: true),
            Wrap(spacing: 10, runSpacing: 4, children: [
              item(dot(JR.riskHigh, ring: true), 'উচ্চ'),
              item(dot(JR.riskMedium, ring: true), 'মাঝারি'),
            ]),
            title('চিহ্ন'),
            Wrap(spacing: 10, runSpacing: 4, children: [
              item(const Icon(Icons.water_drop, size: 14, color: JR.water), 'সমস্যা'),
              item(const Icon(Icons.bolt, size: 14, color: JR.danger), 'বিপদ (তার/ম্যানহোল)'),
              item(const Icon(Icons.cleaning_services, size: 14, color: JR.done), 'অভিযান'),
              item(dot(JR.ink), 'আপনি'),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('ঝাপসা = যাচাই হয়নি, মোটা দাগ = যাচাইকৃত, ✨ = AI যাচাইকৃত ছবি',
                  style: TextStyle(fontSize: 10, color: Colors.black54)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(Widget child) => Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final open = _incidents.where((i) => i.status != Status.resolved).length;
    final myPos = LocationService.position.value;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: const LatLng(AppConfig.dhakaLat, AppConfig.dhakaLon),
            initialZoom: 12.5,
            onTap: (_, p) {
              if (_routeMode) _routeTo(p);
            },
            onLongPress: (_, p) => _openReport(p),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.jolrekha.app',
            ),
            if (_showRisk) CircleLayer(circles: _hotspotCircles()),
            CircleLayer(circles: _depthMode ? _depthCircles() : _heatCircles()),
            if (_route != null)
              PolylineLayer(polylines: [Polyline(points: _route!.points, strokeWidth: 5, color: JR.water)]),
            MarkerLayer(markers: [
              for (final e in _events) Marker(point: e.point, width: 34, height: 34, child: _eventIcon(e)),
              for (final i in _incidents) Marker(point: i.point, width: 36, height: 36, child: _incidentIcon(i)),
              if (myPos != null)
                Marker(
                  point: myPos,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: JR.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
            ]),
            const Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ),
        Positioned(
          left: 12,
          bottom: 22,
          child: _showLegend
              ? _legend()
              : FilledButton.tonalIcon(
                  onPressed: () => setState(() => _showLegend = true),
                  icon: const Icon(Icons.palette_outlined, size: 18),
                  label: const Text('রং'),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _banner(),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Chip(
                  avatar: const Icon(Icons.report, size: 16, color: JR.high),
                  label: Text('এখন $openটি সমস্যা'),
                ),
                FilterChip(
                  selected: _showRisk,
                  label: const Text('ঝুঁকি'),
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  onSelected: (v) => setState(() => _showRisk = v),
                ),
                FilterChip(
                  selected: _depthMode,
                  label: const Text('গভীরতা'),
                  avatar: const Icon(Icons.water, size: 16),
                  onSelected: (v) => setState(() => _depthMode = v),
                ),
                FilterChip(
                  selected: _routeMode,
                  label: Text(_routeMode ? 'গন্তব্যে ট্যাপ করুন' : 'নিরাপদ রুট'),
                  avatar: const Icon(Icons.alt_route, size: 16),
                  onSelected: (v) => setState(() {
                    _routeMode = v;
                    if (!v) _route = null;
                  }),
                ),
              ]),
              if (_depthMode || _routeMode) ...[
                const SizedBox(height: 4),
                _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final v in Vehicle.values)
                      ChoiceChip(
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(vehicleIcon[v], size: 16),
                        label: Text(vehicleLabel[v]!),
                        selected: _vehicle == v,
                        onSelected: (_) => setState(() {
                          _vehicle = v;
                          _route = null; // the old route was for another vehicle
                        }),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    _blockedForVehicle == 0
                        ? '${vehicleLabel[_vehicle]} এর জন্য পানিতে কোনো রাস্তা বন্ধ নেই'
                        : '${vehicleLabel[_vehicle]} এর জন্য $_blockedForVehicleটি জায়গা পার হওয়া যাবে না',
                    style: TextStyle(fontSize: 12, color: _blockedForVehicle == 0 ? JR.done : JR.high),
                  ),
                ])),
              ],
              if (_routing) const LinearProgressIndicator(),
              if (_route != null)
                _card(Row(children: [
                  const Icon(Icons.alt_route, color: JR.water),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_route!.km.toStringAsFixed(1)} কিমি, প্রায় ${_route!.minutes.round()} মিনিট। '
                      '${_route!.avoided}টি সমস্যা/ঝুঁকির জায়গা এড়ানো হয়েছে।',
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _route = null)),
                ])),
            ]),
          ),
        ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'loc',
          onPressed: () => _map.move(_center, 15),
          child: const Icon(Icons.my_location),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'report',
          backgroundColor: JR.ink,
          foregroundColor: Colors.white,
          onPressed: () => _openReport(_center),
          icon: const Icon(Icons.add_location_alt),
          label: const Text('মার্ক করুন'),
        ),
      ]),
    );
  }
}
