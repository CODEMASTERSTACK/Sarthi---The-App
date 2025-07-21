import 'package:flutter/material.dart';
import 'dart:async';
import 'package:torch_controller/torch_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';
import 'package:flutter/services.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({Key? key}) : super(key: key);

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool _sosActive = false;
  Timer? _sosTimer;
  final TorchController _torchController = TorchController();

  @override
  void initState() {
    super.initState();
    _torchController.initialize();
  }

  // Morse code for SOS: ... --- ...
  final List<int> _sosPattern = [
    1, 1, 1, // S: ...
    3, 3, 3, // O: ---
    1, 1, 1, // S: ...
  ];
  final int _dotDuration = 200; // ms
  final int _dashDuration = 600; // ms
  final int _pauseDuration = 200; // ms between signals

  Future<void> _startSOS() async {
    if (_sosActive) return;

    // Request camera permission if not granted
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required for the flashlight.')),
        );
        return;
      }
    }

    setState(() => _sosActive = true);
    // Ensure torch is OFF before starting (toggle if needed)
    await _torchController.toggle();

    // Run SOS pattern in a separate async loop
    _sosTimer = Timer.periodic(
      Duration(milliseconds: (_dotDuration + _pauseDuration) * _sosPattern.length),
      (timer) async {
        for (int i = 0; i < _sosPattern.length; i++) {
          if (!_sosActive) break;
          int duration = _sosPattern[i] == 1 ? _dotDuration : _dashDuration;
          await _torchController.toggle(); // ON
          await Future.delayed(Duration(milliseconds: duration));
          await _torchController.toggle(); // OFF
          await Future.delayed(Duration(milliseconds: _pauseDuration));
        }
      },
    );
  }

  void _stopSOS() {
    setState(() => _sosActive = false);
    _sosTimer?.cancel();
    // Try to turn off the torch if it's on
    _torchController.toggle();
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final accent = Colors.deepPurpleAccent;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Tools', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.1)),
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
      body: Center(
        child: glassCard(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flashlight_on, color: accent, size: 48),
              const SizedBox(height: 12),
              const Text(
                'SOS Flashlight',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _sosActive
                    ? 'Flashlight is sending SOS signal...'
                    : 'Tap the button below to send an SOS signal using your flashlight.',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(_sosActive ? Icons.stop : Icons.sos, color: Colors.white, size: 28),
                label: Text(_sosActive ? 'Stop SOS' : 'Start SOS', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  elevation: 6,
                  shadowColor: accent.withOpacity(0.18),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _sosActive ? _stopSOS : _startSOS,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 