import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui';

import 'widgets/compass.dart';
import 'footprint_page.dart';
import 'tools_page.dart';

class CompassPage extends StatefulWidget {
  const CompassPage({super.key});

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> {
  int _selectedIndex = 0;
  Position? _currentPosition;

  List<Map<String, dynamic>> _waypoints = [];

  @override
  void initState() {
    super.initState();
    _loadWaypoints();
  }

  Future<void> _loadWaypoints() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('waypoints');
    if (saved != null) {
      setState(() {
        _waypoints = saved.map((s) {
          final map = Map<String, dynamic>.from(jsonDecode(s));
          // Ensure time is handled correctly if needed, it's a string now
          return map;
        }).toList();
      });
    }
  }

  Future<void> _saveWaypoints() async {
    final prefs = await SharedPreferences.getInstance();
    // Ensure DateTime is converted to a string before saving
    final List<String> toSave = _waypoints.map((wp) {
      final newWp = Map<String, dynamic>.from(wp);
      if (newWp['time'] is DateTime) {
        newWp['time'] = (newWp['time'] as DateTime).toIso8601String();
      }
      return jsonEncode(newWp);
    }).toList();
    await prefs.setStringList('waypoints', toSave);
  }

  void _onLocationChanged(Position position) {
    setState(() {
      _currentPosition = position;
    });
  }

  void _addWaypoint(Map<String, dynamic> wp) async {
    setState(() {
      _waypoints.add(wp);
    });
    await _saveWaypoints();
  }

  void _deleteWaypoint(Map<String, dynamic> wp) async {
    setState(() {
      _waypoints.remove(wp);
    });
    await _saveWaypoints();
  }

  void _showRouteDialog(Map<String, dynamic> wp) {
    showDialog(
      context: context,
      builder: (ctx) => WaypointRouteDialog(
        currentPosition: _currentPosition,
        waypoint: wp,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      Compass(
        onLocationChanged: _onLocationChanged,
        waypoints: _waypoints,
        onAddWaypoint: _addWaypoint,
        onShowRouteToWaypoint: _showRouteDialog,
        onDeleteWaypoint: _deleteWaypoint,
      ),
      const FootprintPage(),
      const ToolsPage(),
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: Colors.deepPurpleAccent,
            unselectedItemColor: Colors.white54,
            selectedIconTheme: const IconThemeData(size: 32),
            unselectedIconTheme: const IconThemeData(size: 28),
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.deepPurpleAccent,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.white54,
            ),
            showUnselectedLabels: false,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.explore),
                label: 'Compass',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map),
                label: 'Footprint',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.build_rounded),
                label: 'Tools',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WaypointRouteDialog extends StatefulWidget {
  final Position? currentPosition;
  final Map<String, dynamic> waypoint;
  const WaypointRouteDialog({Key? key, required this.currentPosition, required this.waypoint}) : super(key: key);

  @override
  State<WaypointRouteDialog> createState() => _WaypointRouteDialogState();
}

class _WaypointRouteDialogState extends State<WaypointRouteDialog> {
  List<LatLng> _route = [];
  bool _loading = true;
  String? _error;
  double _zoom = 15.0;
  String? _distance;
  String? _duration;
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.currentPosition;
    _fetchRoute();
    _positionStream = Geolocator.getPositionStream().listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _zoomIn() => setState(() => _zoom = (_zoom + 1).clamp(3.0, 18.0));
  void _zoomOut() => setState(() => _zoom = (_zoom - 1).clamp(3.0, 18.0));
  
  void _recenterMap() {
    if (_route.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(_route);
      _mapController.fitBounds(
        bounds,
        options: const FitBoundsOptions(padding: EdgeInsets.all(50.0)),
      );
    }
  }

  Future<void> _fetchRoute() async {
    try {
      final apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjA5NzAxZDRhMTZiZDQ4ZmE4ZDliNGNkNzk3Nzc5MTg1IiwiaCI6Im11cm11cjY0In0=';
      final start = widget.currentPosition;
      final endLat = widget.waypoint['lat'];
      final endLng = widget.waypoint['lng'];
      
      if (start == null) {
        setState(() {
          _error = 'Current location not available.';
          _loading = false;
        });
        return;
      }

      final url =
          'https://api.openrouteservice.org/v2/directions/foot-walking?api_key=$apiKey&start=${start.longitude},${start.latitude}&end=$endLng,$endLat';
      
      final response = await http.get(Uri.parse(url));
      final responseData = jsonDecode(response.body);

      if (response.statusCode != 200) {
        print('Failed to fetch route. Status code: ${response.statusCode}');
        print('Response body: ${response.body}');
        
        // Get error message from API if available
        final errorMessage = responseData['error']?.toString() ?? 'Unknown error occurred';
        setState(() {
          _error = 'Failed to fetch route: $errorMessage';
          _loading = false;
        });
        return;
      }

      // Safely extract route data
      if (responseData['features'] == null || responseData['features'].isEmpty) {
        setState(() {
          _error = 'No route found between these locations.';
          _loading = false;
        });
        return;
      }

      final feature = responseData['features'][0];
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      final summary = properties['summary'];

      if (geometry == null || geometry['coordinates'] == null) {
        setState(() {
          _error = 'Invalid route data received.';
          _loading = false;
        });
        return;
      }

      // Extract route coordinates
      final coords = geometry['coordinates'] as List;
      final route = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

      // Safely extract distance and duration
      String? distance;
      String? duration;
      
      if (summary != null) {
        final distanceMeters = summary['distance'];
        final durationSeconds = summary['duration'];
        
        if (distanceMeters != null) {
          final distanceKm = (distanceMeters as num) / 1000;
          distance = '${distanceKm.toStringAsFixed(2)} km';
        }
        
        if (durationSeconds != null) {
          final durationMin = (durationSeconds as num) / 60;
          duration = '${durationMin.toStringAsFixed(0)} min';
        }
      }

      setState(() {
        _route = route;
        _distance = distance;
        _duration = duration;
        _loading = false;
      });

      // Center the map on the route
      Future.delayed(const Duration(milliseconds: 100), _recenterMap);
      
    } catch (e) {
      print('Error fetching route: $e');
      setState(() {
        _error = 'Could not calculate route. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.deepPurpleAccent;
    final waypointLat = widget.waypoint['lat'];
    final waypointLng = widget.waypoint['lng'];
    final waypointLabel = widget.waypoint['label'];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with title and close button
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.alt_route, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Route to "$waypointLabel"',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            if (_distance != null && _duration != null)
                              Text(
                                '$_distance • $_duration walk',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Map container with controls
                  Container(
                    height: 400,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // Map
                          _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(color: Colors.redAccent),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : FlutterMap(
                                      mapController: _mapController,
                                      options: MapOptions(
                                        center: _route.isNotEmpty
                                            ? _route[0]
                                            : LatLng(_currentPosition?.latitude ?? 0,
                                                _currentPosition?.longitude ?? 0),
                                        zoom: _zoom,
                                        interactiveFlags: InteractiveFlag.all,
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate:
                                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          subdomains: ['a', 'b', 'c'],
                                          userAgentPackageName: 'com.example.compass',
                                        ),
                                        if (_route.isNotEmpty)
                                          PolylineLayer(
                                            polylines: [
                                              Polyline(
                                                points: _route,
                                                color: accent,
                                                strokeWidth: 4.0,
                                                borderColor: Colors.black.withOpacity(0.3),
                                                borderStrokeWidth: 6.0,
                                              ),
                                            ],
                                          ),
                                        MarkerLayer(
                                          markers: [
                                            if (_currentPosition != null)
                                              Marker(
                                                point: LatLng(_currentPosition!.latitude,
                                                    _currentPosition!.longitude),
                                                width: 40,
                                                height: 40,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.greenAccent,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withOpacity(0.3),
                                                        blurRadius: 8,
                                                      ),
                                                    ],
                                                  ),
                                                  child: const Icon(
                                                    Icons.my_location,
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                ),
                                              ),
                                            Marker(
                                              point: LatLng(waypointLat, waypointLng),
                                              width: 40,
                                              height: 40,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: accent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.3),
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.place,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                          // Map controls
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: Column(
                              children: [
                                _MapButton(
                                  icon: Icons.add,
                                  onPressed: _zoomIn,
                                ),
                                const SizedBox(height: 8),
                                _MapButton(
                                  icon: Icons.remove,
                                  onPressed: _zoomOut,
                                ),
                                const SizedBox(height: 8),
                                _MapButton(
                                  icon: Icons.center_focus_strong,
                                  onPressed: _recenterMap,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}