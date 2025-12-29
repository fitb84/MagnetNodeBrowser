import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_client.dart';

class BandwidthScreen extends StatefulWidget {
  const BandwidthScreen({Key? key}) : super(key: key);

  @override
  State<BandwidthScreen> createState() => _BandwidthScreenState();
}

class _BandwidthScreenState extends State<BandwidthScreen> {
  final List<double> _inHistory = [];
  final List<double> _outHistory = [];
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pollBandwidth();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _pollBandwidth());
  }

  Future<void> _pollBandwidth() async {
    try {
      final stats = await ApiClient.getStats();
      final bandwidth = stats['bandwidth'] as Map<String, dynamic>? ?? {};
      
      // Parse bandwidth values from strings like "0 B/s"
      double parseSpeed(String? speedStr) {
        if (speedStr == null || speedStr.isEmpty) return 0.0;
        final match = RegExp(r'([\d.]+)\s*(B|KB|MB|GB)/s').firstMatch(speedStr);
        if (match == null) return 0.0;
        double value = double.tryParse(match.group(1) ?? '0') ?? 0.0;
        switch ((match.group(2) ?? '').toUpperCase()) {
          case 'GB': value *= 1024 * 1024; break;
          case 'MB': value *= 1024; break;
          case 'KB': break;
          case 'B': value /= 1024; break;
        }
        return value;
      }
      
      setState(() {
        if (_inHistory.length > 60) _inHistory.removeAt(0);
        if (_outHistory.length > 60) _outHistory.removeAt(0);
        _inHistory.add(parseSpeed(bandwidth['inrate'] as String?));
        _outHistory.add(parseSpeed(bandwidth['outrate'] as String?));
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Global Bandwidth', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: CustomPaint(
                        painter: _BandwidthChartPainter(_inHistory, _outHistory),
                        child: Container(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text('↓ ${_inHistory.isNotEmpty ? _inHistory.last.toStringAsFixed(1) : '0'} KB/s', style: const TextStyle(color: Colors.blue)),
                        Text('↑ ${_outHistory.isNotEmpty ? _outHistory.last.toStringAsFixed(1) : '0'} KB/s', style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _BandwidthChartPainter extends CustomPainter {
  final List<double> inData;
  final List<double> outData;
  _BandwidthChartPainter(this.inData, this.outData);

  @override
  void paint(Canvas canvas, Size size) {
    final paintIn = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final paintOut = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double maxVal = 1;
    if (inData.isNotEmpty) maxVal = inData.reduce((a, b) => a > b ? a : b);
    if (outData.isNotEmpty) maxVal = maxVal > outData.reduce((a, b) => a > b ? a : b) ? maxVal : outData.reduce((a, b) => a > b ? a : b);
    if (maxVal < 1) maxVal = 1;

    Path pathIn = Path();
    Path pathOut = Path();
    for (int i = 0; i < inData.length; i++) {
      final x = size.width * i / (inData.length - 1).clamp(1, 100);
      final y = size.height - (inData[i] / maxVal) * size.height;
      if (i == 0) pathIn.moveTo(x, y); else pathIn.lineTo(x, y);
    }
    for (int i = 0; i < outData.length; i++) {
      final x = size.width * i / (outData.length - 1).clamp(1, 100);
      final y = size.height - (outData[i] / maxVal) * size.height;
      if (i == 0) pathOut.moveTo(x, y); else pathOut.lineTo(x, y);
    }
    canvas.drawPath(pathIn, paintIn);
    canvas.drawPath(pathOut, paintOut);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}