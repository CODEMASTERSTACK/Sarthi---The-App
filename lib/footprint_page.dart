import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'dart:math' as math;

class CompassNeedleLoader extends StatefulWidget {
  const CompassNeedleLoader({Key? key}) : super(key: key);

  @override
  State<CompassNeedleLoader> createState() => _CompassNeedleLoaderState();
}

class _CompassNeedleLoaderState extends State<CompassNeedleLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Static compass dial
          CustomPaint(
            size: const Size(64, 64),
            painter: _LoaderCompassDialPainter(),
          ),
          // Spinning needle
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * 3.1415926535,
                child: CustomPaint(
                  size: const Size(36, 50),
                  painter: _LoaderNeedlePainter(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoaderCompassDialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    // Dial background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.9),
          Colors.grey.shade400,
          Colors.grey.shade800,
        ],
        stops: [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));
    canvas.drawCircle(center, size.width / 2, bgPaint);
    // Outer ring
    final ringPaint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, size.width / 2 - 1, ringPaint);
    // Cardinal points
    const cardinals = ['N', 'E', 'S', 'W'];
    final textStyle = TextStyle(
      color: Colors.deepPurpleAccent.shade200,
      fontWeight: FontWeight.bold,
      fontSize: 13,
    );
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90 - 90) * 3.1415926535 / 180;
      final textSpan = TextSpan(text: cardinals[i], style: textStyle);
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      final textRadius = radius - 8;
      final offset = Offset(
        center.dx + textRadius * math.cos(angle) - tp.width / 2,
        center.dy + textRadius * math.sin(angle) - tp.height / 2,
      );
      tp.paint(canvas, offset);
    }
    // Center dot
    final dotPaint = Paint()..color = Colors.deepPurpleAccent.shade200;
    canvas.drawCircle(center, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoaderNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint needlePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.deepPurpleAccent.shade200,
          Colors.redAccent.shade200,
          Colors.white,
        ],
        stops: [0.0, 0.7, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final ui.Path needlePath = ui.Path();
    needlePath.moveTo(size.width / 2, 0); // Tip
    needlePath.lineTo(size.width * 0.7, size.height * 0.85); // Bottom right
    needlePath.lineTo(size.width * 0.3, size.height * 0.85); // Bottom left
    needlePath.close();

    // Draw the needle
    canvas.drawPath(needlePath, needlePaint);

    // Draw a metallic circle at the base
    final Paint circlePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey.shade300,
          Colors.grey.shade700,
          Colors.black,
        ],
        stops: [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.85),
        radius: 8,
      ))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.85),
      7,
      circlePaint,
    );
    final Paint centerDotPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.85),
      3.5,
      centerDotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FootprintHistory {
  final List<LatLng> path;
  final double distanceMeters;
  final LatLng start;
  final LatLng end;
  final DateTime timestamp;
  FootprintHistory({
    required this.path,
    required this.distanceMeters,
    required this.start,
    required this.end,
    required this.timestamp,
  });
}

enum MapType { standard, satellite, terrain }

MapType _selectedMapType = MapType.standard;

class FootprintPage extends StatefulWidget {
  const FootprintPage({Key? key}) : super(key: key);

  @override
  State<FootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends State<FootprintPage> {
  List<LatLng> _footprint = [];
  bool _tracking = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  late final MapController _mapController;
  String? _currentAreaName;
  List<FootprintHistory> _history = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = pos;
    });
    _moveMapToCurrent();
    _updateAreaName(pos.latitude, pos.longitude);
  }

  Future<void> _updateAreaName(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        String area = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.country
        ].where((e) => e != null && e.isNotEmpty).join(', ');
        setState(() {
          _currentAreaName = area.isNotEmpty ? area : null;
        });
      }
    } catch (_) {
      setState(() {
        _currentAreaName = null;
      });
    }
  }

  void _moveMapToCurrent() {
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        17.0,
      );
    }
  }

  void _startTracking() {
    setState(() {
      _tracking = true;
      _footprint = [];
    });
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
    ).listen((pos) {
      setState(() {
        _currentPosition = pos;
        _footprint.add(LatLng(pos.latitude, pos.longitude));
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), _mapController.zoom);
      _updateAreaName(pos.latitude, pos.longitude);
    });
  }

  void _stopTracking() {
    if (_footprint.length > 1) {
      final dist = _calculateDistance(_footprint);
      _history.insert(0, FootprintHistory(
        path: List<LatLng>.from(_footprint),
        distanceMeters: dist,
        start: _footprint.first,
        end: _footprint.last,
        timestamp: DateTime.now(),
      ));
    }
    setState(() {
      _tracking = false;
      _footprint = [];
    });
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _clearPath() {
    if (_footprint.length > 1) {
      final dist = _calculateDistance(_footprint);
      _history.insert(0, FootprintHistory(
        path: List<LatLng>.from(_footprint),
        distanceMeters: dist,
        start: _footprint.first,
        end: _footprint.last,
        timestamp: DateTime.now(),
      ));
    }
    setState(() {
      _footprint = [];
    });
  }

  double _calculateDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    final Distance distance = Distance();
    double total = 0.0;
    for (int i = 1; i < points.length; i++) {
      total += distance(points[i - 1], points[i]);
    }
    return total;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Widget glassCard({required Widget child, EdgeInsets? padding, double? width, double? height, Color? color}) {
    final glassColor = color ?? Colors.white.withOpacity(0.08);
    final glassBorder = Colors.white.withOpacity(0.18);
    final glassShadow = [
      BoxShadow(
        color: Colors.black.withOpacity(0.18),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: glassColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glassBorder, width: 1.2),
        boxShadow: glassShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(18),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildMapTypeButton(BuildContext context,
      {required IconData icon,
      required String label,
      required MapType type,
      required bool selected}) {
    final accent = Colors.deepPurpleAccent;
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        setState(() {
          _selectedMapType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? accent : Colors.white.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: selected ? accent : Colors.white.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? userLatLng = _currentPosition == null
        ? null
        : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final accent = Colors.deepPurpleAccent;
    final glassOverlay = Colors.white.withOpacity(0.10);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Footprint', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.1)),
        backgroundColor: Colors.black.withOpacity(0.15),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: userLatLng == null
          ? const Center(child: CompassNeedleLoader())
          : Column(
              children: [
                // Map at the top, with rounded corners at the bottom
                Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.44,
                          width: double.infinity,
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              center: userLatLng,
                              zoom: 17.0,
                              maxZoom: 19.0,
                              minZoom: 3.0,
                              interactiveFlags: InteractiveFlag.all,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: _selectedMapType == MapType.standard
                                    ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png'
                                    : _selectedMapType == MapType.satellite
                                        ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                        : 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                                subdomains: _selectedMapType == MapType.standard || _selectedMapType == MapType.terrain
                                    ? ['a', 'b', 'c']
                                    : [],
                                userAgentPackageName: 'com.example.compass',
                              ),
                              if (_footprint.isNotEmpty)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _footprint,
                                      color: Colors.greenAccent,
                                      strokeWidth: 6.0,
                                      borderStrokeWidth: 2.0,
                                      borderColor: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: userLatLng,
                                    width: 48,
                                    height: 48,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: accent.withOpacity(0.18),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(Icons.person_pin_circle, color: accent, size: 38),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Floating current location button
                      Positioned(
                        bottom: 18,
                        right: 18,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 8,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _moveMapToCurrent,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withOpacity(0.18),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.my_location, color: Colors.white, size: 30),
                            ),
                          ),
                        ),
                      ),
                      // Map type switcher
                      Positioned(
                        top: 18,
                        right: 18,
                        child: glassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMapTypeButton(
                                  context,
                                  icon: Icons.map,
                                  label: 'Default',
                                  type: MapType.standard,
                                  selected: _selectedMapType == MapType.standard,
                                ),
                                _buildMapTypeButton(
                                  context,
                                  icon: Icons.satellite,
                                  label: 'Satellite',
                                  type: MapType.satellite,
                                  selected: _selectedMapType == MapType.satellite,
                                ),
                                _buildMapTypeButton(
                                  context,
                                  icon: Icons.terrain,
                                  label: 'Terrain',
                                  type: MapType.terrain,
                                  selected: _selectedMapType == MapType.terrain,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bottom section: current location, buttons, history
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: glassCard(
                      color: glassOverlay,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Current location info card (already present)
                            glassCard(
                              color: Colors.black.withOpacity(0.72),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, color: Colors.greenAccent.shade400, size: 22),
                                      const SizedBox(width: 7),
                                      const Text('Current Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                                    ],
                                  ),
                                  if (_currentAreaName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                                      child: Text(
                                        _currentAreaName!,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                        softWrap: true,
                                        maxLines: 3,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                  if (_currentPosition != null)
                                    Text(
                                      'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  if (_currentPosition != null)
                                    Text(
                                      'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ),
                            // Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: Icon(_tracking ? Icons.stop : Icons.directions_walk, color: Colors.white, size: 22),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _tracking ? Colors.orange : Colors.greenAccent.shade400,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                      elevation: 4,
                                      shadowColor: accent.withOpacity(0.18),
                                    ),
                                    onPressed: _tracking ? _stopTracking : _startTracking,
                                    label: Text(_tracking ? 'Stop' : 'Capture Footprints', style: const TextStyle(color: Colors.white)),
                                  ),
                                ),
                                if (_footprint.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.delete, color: Colors.white, size: 22),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                        elevation: 4,
                                        shadowColor: Colors.redAccent.withOpacity(0.18),
                                      ),
                                      onPressed: _clearPath,
                                      label: const Text('Clear Path', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 18),
                            // History
                            Row(
                              children: [
                                const Icon(Icons.history, color: Colors.deepPurpleAccent, size: 22),
                                const SizedBox(width: 8),
                                const Text('History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_history.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Text('No footprints yet.', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center),
                              ),
                            if (_history.isNotEmpty)
                              SizedBox(
                                height: 140,
                                child: ListView.separated(
                                  itemCount: _history.length,
                                  separatorBuilder: (ctx, i) => const Divider(height: 10, color: Colors.white12),
                                  itemBuilder: (ctx, i) {
                                    final h = _history[i];
                                    return GestureDetector(
                                      onTap: () async {
                                        final shouldDelete = await showModalBottomSheet<bool>(
                                          context: context,
                                          backgroundColor: Colors.black.withOpacity(0.95),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                                          ),
                                          builder: (ctx) => Padding(
                                            padding: const EdgeInsets.all(20.0),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: const [
                                                    Icon(Icons.history, color: Colors.deepPurpleAccent),
                                                    SizedBox(width: 8),
                                                    Text('Footprint Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.route, color: Colors.greenAccent, size: 18),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      h.distanceMeters >= 1000
                                                          ? '${(h.distanceMeters / 1000).toStringAsFixed(2)} km'
                                                          : '${h.distanceMeters.toStringAsFixed(1)} m',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.place, color: Colors.deepPurpleAccent, size: 16),
                                                    const SizedBox(width: 4),
                                                    Text('From: ${h.start.latitude.toStringAsFixed(5)}, ${h.start.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.flag, color: Colors.orange, size: 16),
                                                    const SizedBox(width: 4),
                                                    Text('To:   ${h.end.latitude.toStringAsFixed(5)}, ${h.end.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.calendar_today, color: Colors.blueGrey, size: 15),
                                                    const SizedBox(width: 4),
                                                    Text('Date: ${h.timestamp.toLocal().toString().substring(0, 16)}', style: const TextStyle(fontSize: 12, color: Colors.white38)),
                                                  ],
                                                ),
                                                const SizedBox(height: 18),
                                                ElevatedButton.icon(
                                                  icon: const Icon(Icons.delete, color: Colors.white),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.redAccent,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                                  ),
                                                  onPressed: () {
                                                    Navigator.of(ctx).pop(true);
                                                  },
                                                  label: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(ctx).pop(false),
                                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                        if (shouldDelete == true) {
                                          setState(() {
                                            _history.removeAt(i);
                                          });
                                        }
                                      },
                                      child: Card(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                        color: Colors.white.withOpacity(0.07),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.route, color: Colors.greenAccent, size: 18),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    h.distanceMeters >= 1000
                                                        ? '${(h.distanceMeters / 1000).toStringAsFixed(2)} km'
                                                        : '${h.distanceMeters.toStringAsFixed(1)} m',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.place, color: Colors.deepPurpleAccent, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text('From: ${h.start.latitude.toStringAsFixed(5)}, ${h.start.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(Icons.flag, color: Colors.orange, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text('To:   ${h.end.latitude.toStringAsFixed(5)}, ${h.end.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(Icons.calendar_today, color: Colors.blueGrey, size: 15),
                                                  const SizedBox(width: 4),
                                                  Text('Date: ${h.timestamp.toLocal().toString().substring(0, 16)}', style: const TextStyle(fontSize: 12, color: Colors.white38)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
} 