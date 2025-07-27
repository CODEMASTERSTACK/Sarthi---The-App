import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';

class Compass extends StatefulWidget {
  const Compass({
    super.key,
    required this.onLocationChanged,
    required this.waypoints,
    this.onAddWaypoint,
    this.onShowRouteToWaypoint,
    this.onDeleteWaypoint,
  });

  final void Function(Position position) onLocationChanged;
  final List<Map<String, dynamic>> waypoints;
  final void Function(Map<String, dynamic> waypoint)? onAddWaypoint;
  final void Function(Map<String, dynamic> waypoint)? onShowRouteToWaypoint;
  final void Function(Map<String, dynamic> waypoint)? onDeleteWaypoint;

  @override
  State<Compass> createState() => _CompassState();
}

class _CompassState extends State<Compass> with WidgetsBindingObserver {
  double? _heading;
  double _prevHeading = 0;
  double _displayHeading = 0;
  bool _hasPermissions = false;
  bool _hasSensor = true;
  Position? _position;
  double? _magneticStrength;
  String? _areaName;
  String? _localTime;
  Timer? _timer;
  StreamSubscription<Position>? _positionStream;
  double? _speed;
  bool _isUncalibrated = false;

  // Remove the local _waypoints list
  // List<Map<String, dynamic>> _waypoints = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    // Make app full screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Listen to location changes
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium, // Lower accuracy to save battery
        distanceFilter: 10, // meters before update
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
        _speed = position.speed; // <-- Add this line
      });
      widget.onLocationChanged(position);
      _getAreaName(position.latitude, position.longitude);
    });

    // Get initial location immediately
    _getInitialLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _positionStream?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      _getInitialLocation(); // Refresh location on resume
    }
  }

  void _updateTime() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _localTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    });
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }
    if (!mounted) return;
    setState(() {
      _hasPermissions = status.isGranted;
    });

    if (_hasPermissions) {
      FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        if (event.heading == null || event.heading!.isNaN) {
          setState(() {
            _hasSensor = false;
          });
          return;
        }
        double normalized = (event.heading! + 360) % 360;
        double? magneticStrength = event.accuracy;

        setState(() {
          _prevHeading = _displayHeading;
          _displayHeading = normalized;
          _heading = normalized;
          _hasSensor = true;
          _magneticStrength = magneticStrength;
          _isUncalibrated = (_magneticStrength ?? 100) <
              30; // Show warning if accuracy is low
        });
      });
    }
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _position = position;
    });
    _getAreaName(position.latitude, position.longitude);
  }

  Future<void> _getInitialLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _position = position;
    });
    widget.onLocationChanged(position);
    _getAreaName(position.latitude, position.longitude);
  }

  Future<void> _getAreaName(double lat, double lng) async {
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

        if (!mounted) return;
        setState(() {
          _areaName = area.isNotEmpty ? area : "Unknown area";
        });

        // If area is found, return early
        if (area.isNotEmpty) return;
      }

      // If no area found, search nearby
      double minDistance = double.infinity;
      Placemark? nearestPlacemark;
      double nearestLat = lat;
      double nearestLng = lng;

      // Try a grid of nearby points (±0.01° ~1km)
      for (double dLat = -0.02; dLat <= 0.02; dLat += 0.01) {
        for (double dLng = -0.02; dLng <= 0.02; dLng += 0.01) {
          if (dLat == 0 && dLng == 0) continue;
          try {
            List<Placemark> nearby = await placemarkFromCoordinates(lat + dLat, lng + dLng);
            if (nearby.isNotEmpty) {
              final place = nearby.first;
              String area = [
                place.name,
                place.street,
                place.subLocality,
                place.locality,
                place.subAdministrativeArea,
                place.administrativeArea,
                place.country
              ].where((e) => e != null && e.isNotEmpty).join(', ');

              if (area.isNotEmpty) {
                double distance = Geolocator.distanceBetween(
                  lat, lng, lat + dLat, lng + dLng,
                );
                if (distance < minDistance) {
                  minDistance = distance;
                  nearestPlacemark = place;
                  nearestLat = lat + dLat;
                  nearestLng = lng + dLng;
                }
              }
            }
          } catch (_) {}
        }
      }

      if (nearestPlacemark != null) {
        String area = [
          nearestPlacemark.name,
          nearestPlacemark.street,
          nearestPlacemark.subLocality,
          nearestPlacemark.locality,
          nearestPlacemark.subAdministrativeArea,
          nearestPlacemark.administrativeArea,
          nearestPlacemark.country
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        if (!mounted) return;
        setState(() {
          _areaName = "$area (approx. ${minDistance.toStringAsFixed(0)} m away)";
        });
      } else {
        if (!mounted) return;
        setState(() {
          _areaName = "Unknown area";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _areaName = "Unknown area";
      });
    }
  }

  String _getCardinalDirection(double heading) {
    const directions = [
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'
    ];
    int index = ((heading + 22.5) ~/ 45) % 8;
    return directions[index];
  }

  double _lerpAngle(double a, double b, double t) {
    double diff = (b - a + 540) % 360 - 180;
    return a + diff * t;
  }

  String _magneticQuality(double? strength) {
    if (strength == null) return "Can't Measure";
    if (strength < 20) return "Weak";
    if (strength < 60) return "Normal";
    return "Strong";
  }

  String _toDMS(double value, String posChar, String negChar) {
    final direction = value >= 0 ? posChar : negChar;
    final absValue = value.abs();
    final degrees = absValue.floor();
    final minutesFull = (absValue - degrees) * 60;
    final minutes = minutesFull.floor();
    final seconds = ((minutesFull - minutes) * 60);
    return "$degrees°${minutes.toString().padLeft(2, '0')}'${seconds.toStringAsFixed(1).padLeft(4, '0')}\"$direction";
  }

  void _saveWaypoint(BuildContext context) async {
    if (_position == null || _heading == null) return;
    final TextEditingController controller = TextEditingController();
    String? label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Save Waypoint', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter label (e.g. Camp, Car)',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      if (!mounted) return;
      final newWaypoint = {
        'label': label,
        'lat': _position!.latitude,
        'lng': _position!.longitude,
        'heading': _heading,
        'time': DateTime.now(),
      };
      if (widget.onAddWaypoint != null) {
        widget.onAddWaypoint!(newWaypoint);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Waypoint "$label" saved!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermissions) {
      return const Center(
        child: Text('Location permission required to use the compass.'),
      );
    }
    if (!_hasSensor) {
      return const Center(
        child: Text('Compass sensor not available on this device.'),
      );
    }
    if (_heading == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final double heading = _heading ?? 0;
    final String direction = _getCardinalDirection(heading);
    final theme = Theme.of(context);
    final accent = Colors.deepPurpleAccent;
    final glassColor = Colors.white.withOpacity(0.08);
    final glassBorder = Colors.white.withOpacity(0.18);
    final glassShadow = [
      BoxShadow(
        color: Colors.black.withOpacity(0.18),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];

    Widget glassCard({required Widget child, EdgeInsets? padding, double? width, double? height}) {
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

    Widget _buildCalibrationWarning() {
      return glassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.explore_off, color: Colors.orangeAccent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Low Compass Accuracy',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wave your device in a figure-8 pattern to calibrate the compass.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.15),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Compass',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            letterSpacing: 1.2,
            fontFamily: 'Montserrat',
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                // Calibration warning
                if (_isUncalibrated) _buildCalibrationWarning(),
                // Area and Time
                if (_areaName != null || _localTime != null)
                  glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_areaName != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _areaName!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_localTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.access_time, color: Colors.deepPurpleAccent, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'Local Time: $_localTime',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.deepPurpleAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                // Compass Dial
                glassCard(
                  padding: const EdgeInsets.all(24),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: _prevHeading,
                      end: _displayHeading,
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      double start = _prevHeading;
                      double end = _displayHeading;
                      double diff = (end - start + 540) % 360 - 180;
                      double shortest = start + diff * ((value - start) / (diff == 0 ? 1 : diff));
                      return SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Compass dial
                            CustomPaint(
                              size: const Size(280, 280),
                              painter: CompassDialPainter(),
                            ),
                            // Needle
                            Transform.rotate(
                              angle: -shortest * math.pi / 180,
                              child: CustomPaint(
                                size: const Size(24, 130),
                                painter: CompassNeedlePainter(),
                              ),
                            ),
                            // Center dot
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade700, width: 2),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Heading
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(
                    '${heading.toStringAsFixed(1)}° $direction',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
                // Info Cards
                if (_position != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: glassCard(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.my_location, color: Colors.greenAccent, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('Latitude', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              SelectableText(
                                _toDMS(_position!.latitude, "N", "S"),
                                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _position!.latitude.toStringAsFixed(6),
                                style: const TextStyle(fontSize: 13, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: glassCard(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.my_location, color: Colors.orangeAccent, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('Longitude', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              SelectableText(
                                _toDMS(_position!.longitude, "E", "W"),
                                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _position!.longitude.toStringAsFixed(6),
                                style: const TextStyle(fontSize: 13, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                // Copy Location button with info
                if (_position != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0, left: 8, right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.flag, color: Colors.white, size: 20),
                            label: const Text('Mark Waypoint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              elevation: 4,
                              shadowColor: Colors.deepPurpleAccent.withOpacity(0.18),
                              textStyle: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _saveWaypoint(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                            label: const Text('Copy Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              elevation: 4,
                              shadowColor: Colors.deepPurpleAccent.withOpacity(0.18),
                              textStyle: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              final dms = '${_toDMS(_position!.latitude, "N", "S")} ${_toDMS(_position!.longitude, "E", "W")}';
                              Clipboard.setData(ClipboardData(text: dms));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('DMS coordinates copied!'),
                                  backgroundColor: Colors.deepPurpleAccent.withOpacity(0.95),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Tooltip(
                          message: 'How to use',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: Colors.grey[900],
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: Row(
                                    children: const [
                                      Icon(Icons.info_outline, color: Colors.deepPurpleAccent),
                                      SizedBox(width: 8),
                                      Text('How to share location?', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                  content: const Text(
                                    "Click copy location button and your coordinates will be copied and you can share them with your family and friends for your location and when they'll paste it in google maps they'll see your coordinate location.",
                                    style: TextStyle(color: Colors.white70, fontSize: 15),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('OK', style: TextStyle(color: Colors.deepPurpleAccent)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withOpacity(0.13),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.info_outline, color: Colors.deepPurpleAccent, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Magnetic strength and speed
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: (_magneticStrength != null)
                          ? glassCard(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.explore, color: Colors.blueGrey, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Magnetic: ${_magneticStrength!.toStringAsFixed(2)} µT (${_magneticQuality(_magneticStrength)})',
                                      style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(height: 48), // Placeholder for equal height
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: (_speed != null)
                          ? glassCard(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.speed, color: Colors.lightGreenAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      (_speed != null && _speed! > 0.5)
                                          ? 'Speed: ${(_speed! * 3.6).toStringAsFixed(2)} km/h'
                                          : 'Speed: 0 km/h',
                                      style: const TextStyle(fontSize: 14, color: Colors.lightGreenAccent, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(height: 48), // Placeholder for equal height
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Waypoints list (if any)
                if (widget.waypoints.isNotEmpty)
                  glassCard(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: SizedBox(
                      height: (widget.waypoints.length > 4) ? 220 : (widget.waypoints.length * 48.0 + 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Waypoints',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: 0.2),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: widget.waypoints.length,
                              separatorBuilder: (context, i) => const Divider(color: Colors.white12, height: 1),
                              itemBuilder: (context, i) {
                                final wp = widget.waypoints[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    final accent = Colors.deepPurpleAccent;
                                    final action = await showModalBottomSheet<String>(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      builder: (ctx) => BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.8),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.18),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 8),
                                              // Handle bar
                                              Container(
                                                width: 40,
                                                height: 4,
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.3),
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                              ),
                                              const SizedBox(height: 20),
                                              // Title
                                              Text(
                                                'Waypoint Options',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.9),
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 20),
                                              // Copy option
                                              ListTile(
                                                leading: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: accent.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Icon(Icons.copy, color: Colors.white),
                                                ),
                                                title: const Text(
                                                  'Copy Coordinates',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                subtitle: const Text(
                                                  'Copy waypoint details to clipboard',
                                                  style: TextStyle(color: Colors.white70),
                                                ),
                                                onTap: () => Navigator.pop(ctx, 'copy'),
                                              ),
                                              // Show Path option
                                              ListTile(
                                                leading: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: accent.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Icon(Icons.alt_route, color: Colors.white),
                                                ),
                                                title: const Text(
                                                  'Show Route',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                subtitle: const Text(
                                                  'View path to this waypoint',
                                                  style: TextStyle(color: Colors.white70),
                                                ),
                                                onTap: () => Navigator.pop(ctx, 'show_path'),
                                              ),
                                              // Delete option
                                              ListTile(
                                                leading: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.redAccent.withOpacity(0.18),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Icon(Icons.delete, color: Colors.redAccent),
                                                ),
                                                title: const Text(
                                                  'Delete Waypoint',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                subtitle: const Text(
                                                  'Remove this waypoint from the list',
                                                  style: TextStyle(color: Colors.white70),
                                                ),
                                                onTap: () => Navigator.pop(ctx, 'delete'),
                                              ),
                                              const SizedBox(height: 20),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                    
                                    if (action == 'copy') {
                                      final text =
                                          '${wp['label']}\nLat: ${wp['lat'].toStringAsFixed(6)}, Lng: ${wp['lng'].toStringAsFixed(6)}\nHeading: ${wp['heading'].toStringAsFixed(1)}°';
                                      Clipboard.setData(ClipboardData(text: text));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('Waypoint copied!'),
                                          backgroundColor: accent.withOpacity(0.95),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                      );
                                    } else if (action == 'show_path' && widget.onShowRouteToWaypoint != null) {
                                      widget.onShowRouteToWaypoint!(wp);
                                    } else if (action == 'delete' && widget.onDeleteWaypoint != null) {
                                      widget.onDeleteWaypoint!(wp);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Icon(Icons.place, color: accent, size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                wp['label'],
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${wp['lat'].toStringAsFixed(5)}, ${wp['lng'].toStringAsFixed(5)}',
                                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '(${wp['heading'].toStringAsFixed(1)}°)',
                                          style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
                                        ),
                                      ],
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
                const SizedBox(height: 80), // For FAB space
              ],
            ),
          ),
        ),  
      ),
    );
  
  }
}

class CompassDialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Metallic radial gradient background
    final Rect rect = Rect.fromCircle(center: center, radius: size.width / 2);
    final Gradient metallicGradient = RadialGradient(
      colors: [
        const Color(0xFFe0e0e0),
        const Color(0xFFb0b0b0),
        const Color(0xFF888888),
        const Color(0xFF444444),
      ],
      stops: [0.0, 0.5, 0.8, 1.0],
      center: Alignment.center,
      focal: Alignment.topLeft,
      focalRadius: 0.1,
    );
    final Paint bgPaint = Paint()..shader = metallicGradient.createShader(rect);
    canvas.drawCircle(center, size.width / 2, bgPaint);

    // Metallic highlight ring
    final Paint ringPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.7),
          Colors.transparent,
          Colors.white.withOpacity(0.7),
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, size.width / 2 - 3, ringPaint);

    final tickPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    final minorTickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.bold,
    );
    final degreeStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.normal,
    );

    // Draw ticks and degree numbers
    for (int i = 0; i < 360; i += 3) {
      final isMajor = i % 30 == 0;
      final tickLength = isMajor ? 16.0 : 8.0;
      final paint = isMajor ? tickPaint : minorTickPaint;
      final angle = (i - 90) * math.pi / 180;
      final p1 = Offset(
        center.dx + (radius - tickLength) * math.cos(angle),
        center.dy + (radius - tickLength) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(p1, p2, paint);

      // Draw degree numbers
      if (isMajor) {
        final textSpan = TextSpan(
          text: '$i',
          style: degreeStyle,
        );
        final tp = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final textAngle = (i - 90) * math.pi / 180;
        final textRadius = radius - 32;
        final offset = Offset(
          center.dx + textRadius * math.cos(textAngle) - tp.width / 2,
          center.dy + textRadius * math.sin(textAngle) - tp.height / 2,
        );
        tp.paint(canvas, offset);
      }
    }

    // Draw cardinal directions
    const cardinals = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90 - 90) * math.pi / 180;
      final textSpan = TextSpan(
        text: cardinals[i],
        style: textStyle,
      );
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      final textRadius = radius - 60;
      final offset = Offset(
        center.dx + textRadius * math.cos(angle) - tp.width / 2,
        center.dy + textRadius * math.sin(angle) - tp.height / 2,
      );
      tp.paint(canvas, offset);
    }

    // Draw cross lines
    final crossPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, center.dy - radius + 30),
        Offset(center.dx, center.dy + radius - 30), crossPaint);
    canvas.drawLine(Offset(center.dx - radius + 30, center.dy),
        Offset(center.dx + radius - 30, center.dy), crossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Needle shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Path needlePath = Path();
    needlePath.moveTo(size.width / 2, 10); // Tip
    needlePath.lineTo(size.width * 0.75, size.height * 0.85); // Bottom right
    needlePath.lineTo(size.width * 0.25, size.height * 0.85); // Bottom left
    needlePath.close();

    // Draw shadow
    canvas.save();
    canvas.translate(2, 8); // Offset shadow a bit
    canvas.drawPath(needlePath, shadowPaint);
    canvas.restore();

    // Metallic gradient for the needle
    final Rect needleRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final Paint needlePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.red.shade900,
          Colors.red,
          Colors.white,
          Colors.red,
          Colors.red.shade900,
        ],
        stops: [0.0, 0.2, 0.5, 0.8, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(needleRect)
      ..style = PaintingStyle.fill;

    // White border
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw the metallic needle
    canvas.drawPath(needlePath, needlePaint);
    canvas.drawPath(needlePath, borderPaint);

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
        radius: 10,
      ))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.85),
      8,
      circlePaint,
    );
    final Paint centerDotPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.85),
      4,
      centerDotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}