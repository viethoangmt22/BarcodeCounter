import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_config.dart';
import '../services/csv_service.dart';
import '../services/prefs_service.dart';
import '../services/scanner_utils.dart';
import '../services/tts_service.dart';

enum ScanResultStatus { idle, ok, ng }

class ScannerProvider extends ChangeNotifier with WidgetsBindingObserver {
  ScannerProvider({required this.config, required this.ttsService}) {
    WidgetsBinding.instance.addObserver(this);
    _loadInitialCounts();
  }

  final ScanConfig config;
  final TtsService ttsService;
  final _prefsService = PrefsService();
  final _csvService = CsvService();

  Future<void> _loadInitialCounts() async {
    final counts = await _prefsService.getPresetCounts(config.signature);
    totalValidCount = counts['ok'] ?? 0;
    totalInvalidCount = counts['ng'] ?? 0;
    
    // Update bag/box counts based on loaded OK count
    bagCount = totalValidCount % config.bagTarget;
    boxCount = totalValidCount % config.boxTarget;
    
    notifyListeners();
  }

  final MobileScannerController scannerController = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    torchEnabled: false,
    // Use unlimited speed for faster response
    detectionSpeed: ScannerUtils.detectionSpeed,
    detectionTimeoutMs:
        ScannerUtils.detectionTimeoutMs, // Restored to detectionTimeoutMs for v7.2.0
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  static const Duration _scanCooldown = Duration(milliseconds: 150);
  static const Duration _duplicateWindow = Duration(milliseconds: 350);
  static const Duration _sameCodeRearmGap = Duration(
    milliseconds: 250,
  ); // Reduced for faster re-scanning
  static const Duration _twoCodeClearGap = Duration(milliseconds: 600);
  static const Duration _sameCodeFallbackGapWithoutCenter = Duration(
    milliseconds: 1200,
  );
  static const double _sameCodePositionTolerancePx = 36;
  static const Duration _requiredComboWindow = Duration(milliseconds: 600);

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

    final detectedCodes = ScannerUtils.pickDetectedCodes(capture);
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

    // In 2-barcode mode, do not fail-fast to NG on a single noisy frame
    // that contains an unexpected decode. Let the common candidate pipeline
    // decide NG after stabilization to avoid false NG while scanning correctly.

    final effectiveCodes = config.requiresTwoCodes
        ? _updateRecentCodes(detectedCodes, now)
        : detectedCodes.toSet();
    final frameSignature = detectedCodes.join('|');
    final unexpectedInFrame = config.requiresTwoCodes
      ? detectedCodes
          .where((code) => !config.requiredCodes.contains(code))
          .toList()
        : <String>[];
    unexpectedInFrame.sort();
    final hasUnexpectedInFrame = unexpectedInFrame.isNotEmpty;
    final isMixedRequiredAndUnexpectedInFrame =
      config.requiresTwoCodes &&
      matchedRequiredInFrame > 0 &&
      hasUnexpectedInFrame;
    final isValid =
      !isMixedRequiredAndUnexpectedInFrame &&
      config.matchesDetectedCodes(effectiveCodes);
    final matchedRequired = config.requiredCodes
        .where((code) => effectiveCodes.contains(code))
        .length;
    final okProcessingKey = 'ok:${config.requiredCodes.join('|')}';

    if (config.requiresTwoCodes &&
      matchedRequired > 0 &&
      !isValid &&
      !hasUnexpectedInFrame) {
      return;
    }

    final processingKey = isValid
      ? okProcessingKey
      : hasUnexpectedInFrame
      ? 'ng:unexpected:${unexpectedInFrame.join('|')}'
      : 'ng:$frameSignature';
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
      unawaited(_handleValid());
      return;
    }

    unawaited(_handleInvalid());
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

      if (!imageSize.isEmpty && ScannerUtils.isInsideCenterRoi(barcode, imageSize)) {
        return center;
      }

      fallbackCenter ??= center;
    }

    return fallbackCenter;
  }

  Offset? _barcodeCenter(Barcode barcode) {
    return ScannerUtils.getBarcodeCenter(barcode);
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

    unawaited(ttsService.speak(config.okMessage));
    unawaited(_prefsService.savePresetCounts(config.signature, totalValidCount, totalInvalidCount));

    String? instruction;
    for (final level in config.alertLevels) {
      if (level.quantity <= 0) {
        continue;
      }
      if (totalValidCount % level.quantity == 0) {
        unawaited(ttsService.speak(level.message));
        instruction = level.message;
      }
    }

    try {
      await _csvService.appendScanLog(
        barcode: config.signature,
        status: 'OK',
        count: totalValidCount,
        instruction: instruction,
      );
    } catch (e) {
      debugPrint('Error logging OK: $e');
    }
  }

  Future<void> _handleInvalid() async {
    totalInvalidCount += 1;
    status = ScanResultStatus.ng;
    notifyListeners();
    unawaited(ttsService.speak(config.ngMessage));
    unawaited(_prefsService.savePresetCounts(config.signature, totalValidCount, totalInvalidCount));

    try {
      await _csvService.appendScanLog(
        barcode: lastScannedCode,
        status: 'NG',
        count: totalValidCount,
      );
    } catch (e) {
      debugPrint('Error logging NG: $e');
    }

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
    unawaited(_prefsService.savePresetCounts(config.signature, 0, 0));
    notifyListeners();
  }

  String get statusLabel {
    switch (status) {
      case ScanResultStatus.ok:
        return 'OK';
      case ScanResultStatus.ng:
        return 'NG';
      case ScanResultStatus.idle:
        return scanningActive ? 'ĐANG QUÉT' : 'TẠM DỪNG';
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
