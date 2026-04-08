import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/scanner_utils.dart';
import '../services/prefs_service.dart';
import '../models/scan_config.dart';

class PresetScanScreen extends StatefulWidget {
  const PresetScanScreen({super.key});

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

  List<ScanPreset> _presets = [];
  String? _statusError;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    PrefsService().getPresets().then((presets) {
      if (mounted) {
        setState(() {
          _presets = presets;
        });
      }
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // Nếu chưa load xong presets thì đợi
    if (_captured || _presets.isEmpty) {
      return;
    }

    final detected = ScannerUtils.pickDetectedCodes(capture);
    if (detected.isEmpty) {
      return;
    }

    final now = DateTime.now();

    for (final code in detected) {
      _recentCodes[code] = now;
    }

    // Tăng timeout lên 2000ms để giữ mã lâu hơn, giúp quét tuần tự 2 mã dễ dàng hơn
    _recentCodes.removeWhere(
      (_, timestamp) =>
          now.difference(timestamp) > const Duration(milliseconds: 2000),
    );

    final effectiveCodes = _recentCodes.keys.toList()..sort();
    if (effectiveCodes.isEmpty) {
      return;
    }

    final key = effectiveCodes.join('|');
    if (_candidateKey == key) {
      _candidateHits++;
    } else {
      _candidateKey = key;
      _candidateHits = 1;
    }

    // Đợi 2 hit để ổn định dải mã
    if (_candidateHits < 2) {
      return;
    }

    // Tìm Preset trùng khớp (effectiveCodes chứa toàn bộ requiredCodes của preset đó)
    ScanPreset? bestMatch;
    for (final preset in _presets) {
      bool isSubset = true;
      for (final reqCode in preset.requiredCodes) {
        if (!effectiveCodes.contains(reqCode)) {
          isSubset = false;
          break;
        }
      }
      
      // Ưu tiên preset cần nhiều barcode nhất (trường hợp bao hàm)
      if (isSubset) {
        if (bestMatch == null ||
            preset.requiredCodes.length > bestMatch.requiredCodes.length) {
          bestMatch = preset;
        }
      }
    }

    if (bestMatch != null) {
      _candidateHits = 0;
      _captured = true;
      await _controller.stop();

      if (!mounted) return;
      // Trả đúng mã yêu cầu của preset để đảm bảo findPresetByRequiredCodes luôn thấy
      Navigator.of(context).pop(bestMatch.requiredCodes);
    } else {
      // Nếu đã ổn định (hit >= 5) mà vẫn không thấy match
      if (_candidateHits >= 5) {
        _showStatusError('Không tìm thấy preset cho mã này');
      }
    }
  }

  void _showStatusError(String message) {
    if (_statusError == message) return;
    
    _statusTimer?.cancel();
    setState(() {
      _statusError = message;
    });

    _statusTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusError = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã mẫu'),
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
                _statusError ?? 'Quét mã mẫu (1 hoặc 2 barcode) để nạp preset tự động.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusError != null ? Colors.redAccent : Colors.white,
                  fontSize: 16,
                  fontWeight: _statusError != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
