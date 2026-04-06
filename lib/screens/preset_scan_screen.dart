import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/scanner_utils.dart';

class PresetScanScreen extends StatefulWidget {
  const PresetScanScreen({required this.requiredCount, super.key});

  final int requiredCount;

  @override
  State<PresetScanScreen> createState() => _PresetScanScreenState();
}

class _PresetScanScreenState extends State<PresetScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: ScannerUtils.detectionSpeed,
    detectionTimeoutMs: ScannerUtils.detectionTimeoutMs,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  bool _captured = false;
  bool _torchOn = false;

  String? _candidateKey;
  int _candidateHits = 0;
  final Map<String, DateTime> _recentCodes = {};

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_captured) {
      return;
    }

    final detected = ScannerUtils.pickDetectedCodes(capture);
    if (detected.isEmpty) {
      return;
    }

    final now = DateTime.now();

    // Strategy for multi-code stabilization
    List<String> effectiveCodes;
    if (widget.requiredCount == 1) {
      effectiveCodes = [detected.first];
    } else {
      for (final code in detected) {
        _recentCodes[code] = now;
      }
      _recentCodes.removeWhere(
        (_, timestamp) =>
            now.difference(timestamp) > const Duration(milliseconds: 900),
      );
      effectiveCodes = _recentCodes.keys.toList()..sort();
      if (effectiveCodes.length < 2) {
        return;
      }
    }

    final key = effectiveCodes.join('|');
    if (_candidateKey == key) {
      _candidateHits++;
    } else {
      _candidateKey = key;
      _candidateHits = 1;
    }

    if (_candidateHits < 2) {
      return;
    }

    _candidateHits = 0;
    _captured = true;
    await _controller.stop();

    if (!mounted) return;
    Navigator.of(context).pop(effectiveCodes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.requiredCount == 2
              ? 'Quet ma mau 2 barcode'
              : 'Quet ma mau 1 barcode',
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await _controller.toggleTorch();
              if (!mounted) {
                return;
              }
              setState(() {
                _torchOn = !_torchOn;
              });
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.requiredCount == 2
                    ? 'Quet 2 barcode mau de nap preset.'
                    : 'Quet 1 barcode mau de nap preset.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
