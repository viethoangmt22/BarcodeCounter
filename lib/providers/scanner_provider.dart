import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_config.dart';
import '../services/tts_service.dart';

enum ScanResultStatus { idle, ok, ng }

class ScannerProvider extends ChangeNotifier with WidgetsBindingObserver {
  ScannerProvider({required this.config, required this.ttsService}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final ScanConfig config;
  final TtsService ttsService;

  final MobileScannerController scannerController = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    torchEnabled: false,
    // Keep duplicate frames so we can enforce our own "2 consecutive hits" rule.
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs:
        300, // Increased from 150ms to 300ms for better accuracy
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
    cameraResolution: const Size(1920, 1080),
  );

  static const Duration _scanCooldown = Duration(milliseconds: 500);
  static const Duration _duplicateWindow = Duration(milliseconds: 1200);
  static const Duration _sameCodeRearmGap = Duration(
    milliseconds: 600,
  ); // Reduced from 900ms to 600ms
  static const Duration _twoCodeClearGap = Duration(milliseconds: 1800);
  static const Duration _sameCodeFallbackGapWithoutCenter = Duration(
    milliseconds: 1800,
  );
  static const double _sameCodePositionTolerancePx = 36;
  static const Duration _requiredComboWindow = Duration(milliseconds: 900);

  int totalValidCount = 0;
  int totalInvalidCount = 0;
  int bagCount = 0;
  int boxCount = 0;

  bool scanningActive = false;
  bool ngLocked = false;
  bool torchOn = false;

  String lastScannedCode = '-';
  ScanResultStatus status = ScanResultStatus.idle;

  DateTime _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? _candidateCode;
  int _candidateHits = 0;
  String? _lastProcessedCode;
  String? _lockedCode;
  final Map<String, DateTime> _lastSeenByKey = {};
  final Map<String, Offset> _acceptedCenterByKey = {};
  final Map<String, DateTime> _recentCodes = {};
  bool _awaitingTwoCodeClear = false;
  DateTime _lastRequiredSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (scanningActive && !ngLocked) {
      return;
    }

    ngLocked = false;
    status = ScanResultStatus.idle;
    scanningActive = true;
    notifyListeners();
    await scannerController.start();
  }

  Future<void> stop() async {
    scanningActive = false;
    ngLocked = false;
    status = ScanResultStatus.idle;
    notifyListeners();
    await scannerController.stop();
  }

  Future<void> resumeAfterNg() async {
    if (!ngLocked) {
      return;
    }

    ngLocked = false;
    scanningActive = true;
    status = ScanResultStatus.idle;
    notifyListeners();
    await scannerController.start();
  }

  Future<void> pauseForNg() async {
    ngLocked = true;
    scanningActive = false;
    status = ScanResultStatus.ng;
    notifyListeners();
    await scannerController.stop();
  }

  Future<void> toggleTorch() async {
    await scannerController.toggleTorch();
    torchOn = !torchOn;
    notifyListeners();
  }

  Future<void> onDetect(BarcodeCapture capture) async {
    if (!scanningActive || ngLocked) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastAcceptedAt) < _scanCooldown) {
      return;
    }

    final detectedCodes = _pickDetectedCodes(capture);
    if (detectedCodes.isEmpty) {
      return;
    }

    lastScannedCode = detectedCodes.join(' | ');
    notifyListeners();

    var matchedRequiredInFrame = 0;
    if (config.requiresTwoCodes) {
      matchedRequiredInFrame = config.requiredCodes
          .where((code) => detectedCodes.contains(code))
          .length;

      // Rearm gate for 2-barcode mode:
      // after one valid count, require a clear gap (no required code visible)
      // before allowing the next count.
      if (_awaitingTwoCodeClear) {
        final clearGapPassed =
            now.difference(_lastRequiredSeenAt) >= _twoCodeClearGap;

        if (matchedRequiredInFrame > 0 && !clearGapPassed) {
          _lastRequiredSeenAt = now;
          return;
        }

        if (matchedRequiredInFrame == 0 && !clearGapPassed) {
          return;
        }

        _awaitingTwoCodeClear = false;
        _recentCodes.clear();
        _candidateCode = null;
        _candidateHits = 0;
      }
    }

    if (config.requiresTwoCodes) {
      final unexpected =
          detectedCodes
              .where((code) => !config.requiredCodes.contains(code))
              .toList()
            ..sort();
      if (unexpected.isNotEmpty) {
        final processingKey = 'ng:unexpected:${unexpected.join('|')}';

        if (_lockedCode == processingKey) {
          final lastSeen = _lastSeenByKey[processingKey];
          if (lastSeen != null &&
              now.difference(lastSeen) < _sameCodeRearmGap) {
            _lastSeenByKey[processingKey] = now;
            return;
          }
          _lockedCode = null;
        }

        if (_lastProcessedCode == processingKey &&
            now.difference(_lastProcessedAt) < _duplicateWindow) {
          return;
        }

        _lastAcceptedAt = now;
        _lastProcessedAt = now;
        _lastProcessedCode = processingKey;
        _lockedCode = processingKey;
        _lastSeenByKey[processingKey] = now;

        await _handleInvalid();
        return;
      }
    }

    final effectiveCodes = config.requiresTwoCodes
        ? _updateRecentCodes(detectedCodes, now)
        : detectedCodes.toSet();
    final frameSignature = detectedCodes.join('|');
    final isValid = config.matchesDetectedCodes(effectiveCodes);
    final matchedRequired = config.requiredCodes
        .where((code) => effectiveCodes.contains(code))
        .length;
    final okProcessingKey = 'ok:${config.requiredCodes.join('|')}';

    if (config.requiresTwoCodes && matchedRequired > 0 && !isValid) {
      return;
    }

    final processingKey = isValid ? okProcessingKey : 'ng:$frameSignature';
    final lockedCodeCenter =
        !config.requiresTwoCodes && detectedCodes.length == 1
        ? _findCenterForCode(capture, detectedCodes.first)
        : null;

    // Anti-duplicate lock: after a code is accepted, require a short gap
    // (barcode moved out of view) before allowing the same value again.
    if (_lockedCode == processingKey) {
      final lastSeen = _lastSeenByKey[processingKey];
      _lastSeenByKey[processingKey] = now;

      if (!config.requiresTwoCodes) {
        final acceptedCenter = _acceptedCenterByKey[processingKey];
        if (_isSameSpot(acceptedCenter, lockedCodeCenter)) {
          return;
        }
      }

      final requiredGap =
          (!config.requiresTwoCodes &&
              (_acceptedCenterByKey[processingKey] == null ||
                  lockedCodeCenter == null))
          ? _sameCodeFallbackGapWithoutCenter
          : _sameCodeRearmGap;

      if (lastSeen != null && now.difference(lastSeen) < requiredGap) {
        return;
      }
      _lockedCode = null;
    }

    if (_candidateCode == processingKey) {
      _candidateHits += 1;
    } else {
      _candidateCode = processingKey;
      _candidateHits = 1;
    }

    if (_candidateHits < 2) {
      return;
    }

    _candidateHits = 0;

    if (_lastProcessedCode == processingKey &&
        now.difference(_lastProcessedAt) < _duplicateWindow) {
      return;
    }

    _lastAcceptedAt = now;
    _lastProcessedAt = now;
    _lastProcessedCode = processingKey;
    _lockedCode = processingKey;
    _lastSeenByKey[processingKey] = now;
    if (config.requiresTwoCodes) {
      if (isValid) {
        _awaitingTwoCodeClear = true;
        _lastRequiredSeenAt = now;
      }
    } else if (lockedCodeCenter != null) {
      _acceptedCenterByKey[processingKey] = lockedCodeCenter;
    }

    if (isValid) {
      await _handleValid();
      return;
    }

    await _handleInvalid();
  }

  Set<String> _updateRecentCodes(Iterable<String> codes, DateTime now) {
    for (final code in codes) {
      _recentCodes[code] = now;
    }

    _recentCodes.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _requiredComboWindow,
    );

    return _recentCodes.keys.toSet();
  }

  List<String> _pickDetectedCodes(BarcodeCapture capture) {
    final imageSize = capture.size;
    if (capture.barcodes.isEmpty) {
      return const [];
    }

    final centerCodes = <String>{};
    for (final barcode in capture.barcodes) {
      if (_isInsideCenterRoi(barcode, imageSize)) {
        final value = (barcode.rawValue ?? '').trim();
        if (value.isNotEmpty) {
          centerCodes.add(value);
        }
      }
    }

    if (centerCodes.isNotEmpty) {
      final values = centerCodes.toList()..sort();
      return values;
    }

    // Some devices/formats may not provide reliable corner points.
    // Fallback to all detected barcodes to avoid "no response" behavior.
    final fallback =
        capture.barcodes
            .map((e) => (e.rawValue ?? '').trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return fallback;
  }

  bool _isInsideCenterRoi(Barcode barcode, Size imageSize) {
    final corners = barcode.corners;
    if (corners.isEmpty || imageSize.isEmpty) {
      return false;
    }

    final minX = corners.map((p) => p.dx).reduce(min);
    final maxX = corners.map((p) => p.dx).reduce(max);
    final minY = corners.map((p) => p.dy).reduce(min);
    final maxY = corners.map((p) => p.dy).reduce(max);

    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    final roiRect = Rect.fromLTWH(
      imageSize.width * 0.25,
      imageSize.height * 0.25,
      imageSize.width * 0.5,
      imageSize.height * 0.5,
    );

    return roiRect.contains(center);
  }

  Offset? _findCenterForCode(BarcodeCapture capture, String code) {
    final imageSize = capture.size;
    Offset? fallbackCenter;

    for (final barcode in capture.barcodes) {
      final value = (barcode.rawValue ?? '').trim();
      if (value != code) {
        continue;
      }

      final center = _barcodeCenter(barcode);
      if (center == null) {
        continue;
      }

      if (!imageSize.isEmpty && _isInsideCenterRoi(barcode, imageSize)) {
        return center;
      }

      fallbackCenter ??= center;
    }

    return fallbackCenter;
  }

  Offset? _barcodeCenter(Barcode barcode) {
    final corners = barcode.corners;
    if (corners.isEmpty) {
      return null;
    }

    final minX = corners.map((p) => p.dx).reduce(min);
    final maxX = corners.map((p) => p.dx).reduce(max);
    final minY = corners.map((p) => p.dy).reduce(min);
    final maxY = corners.map((p) => p.dy).reduce(max);
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  bool _isSameSpot(Offset? first, Offset? second) {
    if (first == null || second == null) {
      return false;
    }

    return (first - second).distance <= _sameCodePositionTolerancePx;
  }

  Future<void> _handleValid() async {
    totalValidCount += 1;
    bagCount = totalValidCount % config.bagTarget;
    boxCount = totalValidCount % config.boxTarget;
    status = ScanResultStatus.ok;
    notifyListeners();

    await ttsService.speak(config.okMessage);

    for (final level in config.alertLevels) {
      if (level.quantity <= 0) {
        continue;
      }

      if (totalValidCount % level.quantity == 0) {
        await ttsService.speak(level.message);
      }
    }
  }

  Future<void> _handleInvalid() async {
    totalInvalidCount += 1;
    status = ScanResultStatus.ng;
    notifyListeners();
    await ttsService.speak(config.ngMessage);
    await pauseForNg();
  }

  void resetCounters() {
    totalValidCount = 0;
    totalInvalidCount = 0;
    bagCount = 0;
    boxCount = 0;
    lastScannedCode = '-';
    status = ScanResultStatus.idle;
    _candidateCode = null;
    _candidateHits = 0;
    _lastProcessedCode = null;
    _lockedCode = null;
    _lastSeenByKey.clear();
    _acceptedCenterByKey.clear();
    _awaitingTwoCodeClear = false;
    _lastRequiredSeenAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _recentCodes.clear();
    notifyListeners();
  }

  String get statusLabel {
    switch (status) {
      case ScanResultStatus.ok:
        return 'OK';
      case ScanResultStatus.ng:
        return 'NG';
      case ScanResultStatus.idle:
        return scanningActive ? 'SCANNING' : 'PAUSED';
    }
  }

  Color get statusColor {
    switch (status) {
      case ScanResultStatus.ok:
        return Colors.green;
      case ScanResultStatus.ng:
        return Colors.red;
      case ScanResultStatus.idle:
        return Colors.orange;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      scannerController.stop();
      return;
    }

    if (state == AppLifecycleState.resumed && scanningActive && !ngLocked) {
      scannerController.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scannerController.dispose();
    unawaited(ttsService.dispose());
    super.dispose();
  }
}
