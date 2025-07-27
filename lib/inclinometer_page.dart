import 'package:flutter/material.dart';
import 'package:motion_sensors/motion_sensors.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:async';

class InclinometerPage extends StatefulWidget {
  const InclinometerPage({Key? key}) : super(key: key);

  @override
  State<InclinometerPage> createState() => _InclinometerPageState();
}

class _InclinometerPageState extends State<InclinometerPage> {
  double _pitch = 0.0;
  double _roll = 0.0;
  late final StreamSubscription<OrientationEvent> _orientationSubscription;

  @override
  void initState() {
    super.initState();
    _orientationSubscription = motionSensors.orientation.listen((event) {
      if (!mounted) return;
      setState(() {
        _pitch = event.pitch * 180 / math.pi;
        _roll = event.roll * 180 / math.pi;
      });
    });
  }

  @override
  void dispose() {
    _orientationSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.deepPurpleAccent;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Inclination', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.black.withOpacity(0.15),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Center(
        child: _glassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.device_hub, color: accent, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Inclinometer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Useful for hikers and engineers to measure slope or angle.',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _angleDisplay('Pitch', _pitch, accent),
              const SizedBox(height: 12),
              _angleDisplay('Roll', _roll, Colors.orangeAccent),
              const SizedBox(height: 24),
              _visualIndicator(_pitch, _roll),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
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
            padding: const EdgeInsets.all(18),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _angleDisplay(String label, double value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.straighten, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          '$label: ${value.toStringAsFixed(1)}°',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _visualIndicator(double pitch, double roll) {
    // Simple bubble level visualization
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _BubbleLevelPainter(pitch: pitch, roll: roll),
      ),
    );
  }
}

class _BubbleLevelPainter extends CustomPainter {
  final double pitch;
  final double roll;

  _BubbleLevelPainter({required this.pitch, required this.roll});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw outer circle
    final Paint circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw cross lines
    final Paint crossPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), crossPaint);
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), crossPaint);

    // Bubble position (simulate based on pitch/roll)
    double bubbleX = center.dx + roll / 90 * radius;
    double bubbleY = center.dy - pitch / 90 * radius;

    // Clamp bubble within circle
    final dx = bubbleX - center.dx;
    final dy = bubbleY - center.dy;
    if (math.sqrt(dx * dx + dy * dy) > radius - 10) {
      final angle = math.atan2(dy, dx);
      bubbleX = center.dx + (radius - 10) * math.cos(angle);
      bubbleY = center.dy + (radius - 10) * math.sin(angle);
    }

    // Draw bubble
    final Paint bubblePaint = Paint()
      ..color = Colors.lightGreenAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(bubbleX, bubbleY), 14, bubblePaint);

    // Bubble border
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(bubbleX, bubbleY), 14, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}