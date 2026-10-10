import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const DaleeniApp());

class AppColors {
  static const lapis = Color(0xFF1B3F8B);
  static const gold = Color(0xFFF2B134);
  static const palm = Color(0xFF2E7D4F);
  static const danger = Color(0xFFD64545);
  static const surface = Color(0xFFF3F6FB);
}

class DaleeniApp extends StatelessWidget {
  const DaleeniApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.lapis,
        secondary: AppColors.gold,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    return MaterialApp(
      title: 'دليني',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: base.copyWith(
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      ),
      home: const HomeMapScreen(),
    );
  }
}

String arDigits(Object n) {
  const west = '0123456789';
  const east = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((c) {
    final i = west.indexOf(c);
    return i == -1 ? c : east[i];
  }).join();
}

String timeAgo(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'هسه';
  if (m < 60) return 'قبل ${arDigits(m)} دقيقة';
  final h = m ~/ 60;
  if (h < 24) return 'قبل ${arDigits(h)} ساعة';
  return 'قبل ${arDigits(h ~/ 24)} يوم';
}

String levelTitle(int points) {
  if (points >= 2000) return 'شيخ الدرب';
  if (points >= 500) return 'أبو الدرب';
  if (points >= 100) return 'سائق خبرة';
  return 'سواق جديد';
}

enum ReportType {
  jam('زحمة خانقة', '🚗', Color(0xFFD64545), Duration(minutes: 45)),
  brokenCar('سيارة عاطلة', '🛠️', Color(0xFFE08A1E), Duration(hours: 1)),
  pothole('مطب أو حفرة', '🕳️', Color(0xFF8D6E63), Duration(days: 3)),
  checkpoint('سيطرة مرورية', '🚧', Color(0xFF1B3F8B), Duration(hours: 3)),
  closedRoad('شارع مغلق', '⛔', Color(0xFF6A1B9A), Duration(hours: 6)),
  camera('كاميرا أو رادار', '📸', Color(0xFF00897B), Duration(days: 30));

  const ReportType(this.label, this.emoji, this.color, this.ttl);

  final String label;
  final String emoji;
  final Color color;
  final Duration ttl;
}

class Report {
  Report({
    required this.id,
    required this.type,
    required this.position,
    required this.createdAt,
    this.confirmations = 0,
    this.denials = 0,
  });

  final String id;
  final ReportType type;
  final LatLng position;
  final DateTime createdAt;
  int confirmations;
  int denials;

  DateTime get expiresAt => createdAt.add(type.ttl);
  bool get isActive => DateTime.now().isBefore(expiresAt);
}

abstract class ReportRepository {
  List<Report> get current;
  Stream<List<Report>> get stream;
  Future<void> submit(ReportType type, LatLng position);
  Future<void> vote(String id, {required bool stillThere});
}

class MockReportRepository implements ReportRepository {
  MockReportRepository() {
    final now = DateTime.now();
    _items.addAll([
      Report(
        id: 'a1',
        type: ReportType.jam,
        position: const LatLng(33.3128, 44.3615),
        createdAt: now.subtract(const Duration(minutes: 7)),
        confirmations: 4,
      ),
      Report(
        id: 'a2',
        type: ReportType.checkpoint,
        position: const LatLng(33.3052, 44.4021),
        createdAt: now.subtract(const Duration(minutes: 40)),
        confirmations: 2,
      ),
      Report(
        id: 'a3',
        type: ReportType.pothole,
        position: const LatLng(33.3290, 44.3890),
        createdAt: now.subtract(const Duration(hours: 5)),
        confirmations: 9,
      ),
      Report(
        id: 'a4',
        type: ReportType.camera,
        position: const LatLng(33.3201, 44.3512),
        createdAt: now.subtract(const Duration(days: 2)),
        confirmations: 12,
      ),
    ]);
  }

  final _items = <Report>[];
  final _ctrl = StreamController<List<Report>>.broadcast();

  @override
  List<Report> get current => _items.where((r) => r.isActive).toList();

  @override
  Stream<List<Report>> get stream => _ctrl.stream;

  void _emit() => _ctrl.add(current);

  @override
  Future<void> submit(ReportType type, LatLng position) async {
    _items.add(Report(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      position: position,
      createdAt: DateTime.now(),
    ));
    _emit();
  }

  @override
  Future<void> vote(String id, {required bool stillThere}) async {
    final r = _items.firstWhere((e) => e.id == id);
    if (stillThere) {
      r.confirmations++;
    } else {
      r.denials++;
      if (r.denials >= 3 && r.denials > r.confirmations) _items.remove(r);
    }
    _emit();
  }
}

class IraqiVoice {
  static const straight = 'كمّل دغري';
  static const uTurn = 'سوّي دوران عند أول فرصة';
  static const rerouting = 'لحظة، أدوّر لك طريق ثاني';
  static const arrived = 'وصلنا، الله يسلمك!';

  static String turnRight(int m) => 'بعد ${arDigits(m)} متر، دور يمين';
  static String turnLeft(int m) => 'بعد ${arDigits(m)} متر، دور يسار';

  static String warn(ReportType t, int m) => switch (t) {
        ReportType.jam => 'دير بالك، زحمة بعد ${arDigits(m)} متر',
        ReportType.brokenCar => 'سيارة عاطلة بالطريق، خفف السرعة',
        ReportType.pothole => 'دير بالك، مطب قدامك',
        ReportType.checkpoint => 'سيطرة بعد ${arDigits(m)} متر',
        ReportType.closedRoad => 'الشارع مغلق قدامك، أدوّر لك طريق ثاني',
        ReportType.camera => 'كاميرا بعد ${arDigits(m)} متر، خفف السرعة',
      };
}

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  static const _baghdad = LatLng(33.3152, 44.3661);

  final _map = MapController();
  final ReportRepository _repo = MockReportRepository();

  StreamSubscription<List<Report>>? _reportsSub;
  StreamSubscription<Position>? _positionSub;

  List<Report> _reports = [];
  LatLng? _me;
  int _points = 120;

  @override
  void initState() {
    super.initState();
    _reports = _repo.current;
    _reportsSub = _repo.stream.listen((list) {
      if (mounted) setState(() => _reports = list);
    });
    _startLocation();
  }

  @override
  void dispose() {
    _reportsSub?.cancel();
    _positionSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((p) {
      final here = LatLng(p.latitude, p.longitude);
      final first = _me == null;
      if (!mounted) return;
      setState(() => _me = here);
      if (first) _map.move(here, 16);
    });
  }

  void _recenter() {
    final me = _me;
    if (me != null) _map.move(me, 16);
  }

  Future<void> _submit(ReportType type) async {
    Navigator.of(context).pop();
    HapticFeedback.mediumImpact();
    final pos = _me ?? _map.camera.center;
    await _repo.submit(type, pos);
    if (!mounted) return;
    setState(() => _points += 10);
    _toast('يعطيك العافية! وصل بلاغ ${type.label}، وزادت نقاطك ١٠');
  }

  Future<void> _vote(Report r, bool stillThere) async {
    Navigator.of(context).pop();
    HapticFeedback.selectionClick();
    await _repo.vote(r.id, stillThere: stillThere);
    if (!mounted) return;
    setState(() => _points += 2);
    _toast('تسلم إيدك!');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 112),
      ));
  }

  void _openQuickReport() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'شنو شفت بالطريق؟',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  for (final t in ReportType.values)
                    _QuickReportTile(type: t, onTap: () => _submit(t)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReport(Report r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${r.type.emoji}  ${r.type.label}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${timeAgo(r.createdAt)}، أكدها ${arDigits(r.confirmations)} سائقين',
                style: const TextStyle(color: Colors.black54, fontSize: 15),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _BigButton(
                      label: 'بعده موجود',
                      color: AppColors.palm,
                      onTap: () => _vote(r, true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BigButton(
                      label: 'راح',
                      color: AppColors.danger,
                      onTap: () => _vote(r, false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: _baghdad,
              initialZoom: 13,
              minZoom: 5,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'iq.daleeni.app',
              ),
              MarkerLayer(
                markers: [
                  for (final r in _reports)
                    Marker(
                      point: r.position,
                      width: 56,
                      height: 56,
                      child: GestureDetector(
                        onTap: () => _showReport(r),
                        child: _ReportPin(type: r.type),
                      ),
                    ),
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 28,
                      height: 28,
                      child: const _MeDot(),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _TopBar(points: _points),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'locate',
                      onPressed: _recenter,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 72,
                        child: FilledButton.icon(
                          onPressed: _openQuickReport,
                          icon: const Icon(Icons.campaign_rounded, size: 32),
                          label: const Text(
                            'بلّغ',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            elevation: 3,
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {},
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('على وين رايح؟', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          elevation: 3,
          color: AppColors.lapis,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  levelTitle(points),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${arDigits(points)} نقطة',
                  style: const TextStyle(color: AppColors.gold, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickReportTile extends StatelessWidget {
  const _QuickReportTile({required this.type, required this.onTap});

  final ReportType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: type.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(type.emoji, style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 6),
            Text(
              type.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ReportPin extends StatelessWidget {
  const _ReportPin({required this.type});

  final ReportType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: type.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Text(type.emoji, style: const TextStyle(fontSize: 24)),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2F80ED),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
    );
  }
}
