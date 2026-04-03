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
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 150,
    formats: [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
    cameraResolution: const Size(1920, 1080),
  );

  static const Duration _scanCooldown = Duration(milliseconds: 500);
  static const Duration _duplicateWindow = Duration(milliseconds: 1200);

  int totalValidCount = 0;
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

    final barcode = _pickCenterBarcode(capture);
    if (barcode == null) {
      return;
    }

    final code = (barcode.rawValue ?? '').trim();
    if (code.isEmpty) {
      return;
    }

    lastScannedCode = code;
    notifyListeners();

    if (_candidateCode == code) {
      _candidateHits += 1;
    } else {
      _candidateCode = code;
      _candidateHits = 1;
    }

    if (_candidateHits < 2) {
      return;
    }

    _candidateHits = 0;

    if (_lastProcessedCode == code &&
        now.difference(_lastProcessedAt) < _duplicateWindow) {
      return;
    }

    _lastAcceptedAt = now;
    _lastProcessedAt = now;
    _lastProcessedCode = code;

    if (code == config.masterCode) {
      await _handleValid();
      return;
    }

    await _handleInvalid();
  }

  Barcode? _pickCenterBarcode(BarcodeCapture capture) {
    final imageSize = capture.size;
    if (capture.barcodes.isEmpty) {
      return null;
    }

    for (final barcode in capture.barcodes) {
      if (_isInsideCenterRoi(barcode, imageSize)) {
        return barcode;
      }
    }

    return null;
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

  Future<void> _handleValid() async {
    totalValidCount += 1;
    bagCount += 1;
    boxCount += 1;
    status = ScanResultStatus.ok;
    notifyListeners();

    await ttsService.speak('OK con dê');

    if (bagCount >= config.bagTarget) {
      bagCount = 0;
      notifyListeners();
      await ttsService.speak(
        'Đủ ${config.bagTarget} cái rồi đóng túi nilon đi',
      );
    }

    if (totalValidCount % config.boxTarget == 0) {
      boxCount = 0;
      notifyListeners();
      await ttsService.speak('Đủ ${config.boxTarget} cái rồi đóng thùng đi');
    }
  }

  Future<void> _handleInvalid() async {
    status = ScanResultStatus.ng;
    notifyListeners();
    await ttsService.speak('NG NG NG. Sai tem giấy rồi');
    await pauseForNg();
  }

  void resetCounters() {
    totalValidCount = 0;
    bagCount = 0;
    boxCount = 0;
    lastScannedCode = '-';
    status = ScanResultStatus.idle;
    _candidateCode = null;
    _candidateHits = 0;
    _lastProcessedCode = null;
    _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
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
