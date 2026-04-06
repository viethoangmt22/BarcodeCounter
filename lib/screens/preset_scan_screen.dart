import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PresetScanScreen extends StatefulWidget {
  const PresetScanScreen({required this.requiredCount, super.key});

  final int requiredCount;

  @override
  State<PresetScanScreen> createState() => _PresetScanScreenState();
}

class _PresetScanScreenState extends State<PresetScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  static const Duration _duplicateWindow = Duration(milliseconds: 1200);
  static const Duration _requiredComboWindow = Duration(milliseconds: 900);

  bool _captured = false;
  bool _torchOn = false;

  String? _candidateKey;
  int _candidateHits = 0;
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastProcessedKey;
  final Map<String, DateTime> _recentCodes = {};

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_captured || capture.barcodes.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final codes = <String>{};
    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? '').trim();
      if (code.isNotEmpty) {
        codes.add(code);
      }
    }

    if (codes.isEmpty) {
      return;
    }

    List<String> effectiveCodes;
    if (widget.requiredCount == 1) {
      final sorted = codes.toList()..sort();
      effectiveCodes = <String>[sorted.first];
    } else {
      for (final code in codes) {
        _recentCodes[code] = now;
      }

      _recentCodes.removeWhere(
        (_, timestamp) => now.difference(timestamp) > _requiredComboWindow,
      );

      effectiveCodes = _recentCodes.keys.toList()..sort();
      if (effectiveCodes.length < 2) {
        return;
      }
    }

    final candidateKey = effectiveCodes.join('|');

    if (widget.requiredCount == 2) {
      if (_candidateKey == candidateKey) {
        _candidateHits += 1;
      } else {
        _candidateKey = candidateKey;
        _candidateHits = 1;
      }

      if (_candidateHits < 2) {
        return;
      }
    }

    if (_lastProcessedKey == candidateKey &&
        now.difference(_lastProcessedAt) < _duplicateWindow) {
      return;
    }

    _lastProcessedKey = candidateKey;
    _lastProcessedAt = now;

    _captured = true;
    await _controller.stop();

    if (!mounted) {
      return;
    }

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
