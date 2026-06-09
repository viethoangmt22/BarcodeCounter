import 'dart:async';

import 'package:flutter/material.dart';

import '../models/scan_config.dart';
import '../services/csv_service.dart';
import '../services/prefs_service.dart';
import '../services/tts_service.dart';

enum UsbScanStatus { idle, ok, ng }

class UsbScannerProvider extends ChangeNotifier {
  UsbScannerProvider({required this.config, required this.ttsService}) {
    _loadInitialCounts();
  }

  final ScanConfig config;
  final TtsService ttsService;
  final _prefsService = PrefsService();
  final _csvService = CsvService();

  int totalValidCount = 0;
  int totalInvalidCount = 0;
  int bagCount = 0;
  int boxCount = 0;

  bool scanningActive = true;
  bool ngLocked = false;

  String lastScannedCode = '-';
  UsbScanStatus status = UsbScanStatus.idle;

  // Buffer to store scanned required codes for dual barcode mode
  final List<String> scannedCodesBuffer = [];
  Timer? _bufferTimer;
  static const Duration _bufferTimeout = Duration(seconds: 5);

  Future<void> _loadInitialCounts() async {
    final counts = await _prefsService.getPresetCounts(config.signature);
    totalValidCount = counts['ok'] ?? 0;
    totalInvalidCount = counts['ng'] ?? 0;

    // Update bag/box counts based on loaded OK count
    bagCount = totalValidCount % config.bagTarget;
    boxCount = totalValidCount % config.boxTarget;

    notifyListeners();
  }

  void handleBarcodeScanned(String barcode) {
    if (!scanningActive || ngLocked) {
      return;
    }

    final code = barcode.trim();
    if (code.isEmpty) return;

    lastScannedCode = code;

    if (!config.requiresTwoCodes) {
      // Single barcode mode
      final isValid = config.matchesDetectedCodes([code]);
      if (isValid) {
        unawaited(_handleValid());
      } else {
        unawaited(_handleInvalid(code));
      }
    } else {
      // Dual barcode mode
      if (!config.requiredCodes.contains(code)) {
        // Unexpected code scanned -> NG immediately!
        unawaited(_handleInvalid(code));
      } else {
        // Valid required code scanned
        if (scannedCodesBuffer.contains(code)) {
          // Already scanned this code in this cycle, ignore duplicate
          return;
        }

        scannedCodesBuffer.add(code);
        _resetBufferTimer();

        // Check if both required codes are now scanned
        final containsAll = config.requiredCodes.every(scannedCodesBuffer.contains);
        if (containsAll) {
          _bufferTimer?.cancel();
          scannedCodesBuffer.clear();
          unawaited(_handleValid());
        } else {
          status = UsbScanStatus.idle;
          notifyListeners();
        }
      }
    }
  }

  void _resetBufferTimer() {
    _bufferTimer?.cancel();
    _bufferTimer = Timer(_bufferTimeout, () {
      if (scannedCodesBuffer.isNotEmpty) {
        scannedCodesBuffer.clear();
        notifyListeners();
      }
    });
  }

  Future<void> resumeAfterNg() async {
    if (!ngLocked) {
      return;
    }

    ngLocked = false;
    scanningActive = true;
    status = UsbScanStatus.idle;
    scannedCodesBuffer.clear();
    notifyListeners();
  }

  Future<void> _handleValid() async {
    totalValidCount += 1;
    bagCount = totalValidCount % config.bagTarget;
    boxCount = totalValidCount % config.boxTarget;
    status = UsbScanStatus.ok;
    notifyListeners();

    unawaited(ttsService.speak(config.okMessage));
    unawaited(
      _prefsService.savePresetCounts(
        config.signature,
        totalValidCount,
        totalInvalidCount,
      ),
    );

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
      debugPrint('Error logging USB OK: $e');
    }
  }

  Future<void> _handleInvalid(String scannedCode) async {
    totalInvalidCount += 1;
    status = UsbScanStatus.ng;
    ngLocked = true;
    scanningActive = false;
    scannedCodesBuffer.clear();
    notifyListeners();

    unawaited(ttsService.speak(config.ngMessage));
    unawaited(
      _prefsService.savePresetCounts(
        config.signature,
        totalValidCount,
        totalInvalidCount,
      ),
    );

    try {
      await _csvService.appendScanLog(
        barcode: scannedCode,
        status: 'NG',
        count: totalValidCount,
      );
    } catch (e) {
      debugPrint('Error logging USB NG: $e');
    }
  }

  void resetCounters() {
    totalValidCount = 0;
    totalInvalidCount = 0;
    bagCount = 0;
    boxCount = 0;
    lastScannedCode = '-';
    status = UsbScanStatus.idle;
    scannedCodesBuffer.clear();
    _bufferTimer?.cancel();
    unawaited(_prefsService.savePresetCounts(config.signature, 0, 0));
    notifyListeners();
  }

  String get statusLabel {
    switch (status) {
      case UsbScanStatus.ok:
        return 'OK';
      case UsbScanStatus.ng:
        return 'NG';
      case UsbScanStatus.idle:
        return scanningActive ? 'ĐANG QUÉT' : 'TẠM DỪNG';
    }
  }

  Color get statusColor {
    switch (status) {
      case UsbScanStatus.ok:
        return Colors.green;
      case UsbScanStatus.ng:
        return Colors.red;
      case UsbScanStatus.idle:
        return Colors.orange;
    }
  }

  @override
  void dispose() {
    _bufferTimer?.cancel();
    unawaited(ttsService.dispose());
    super.dispose();
  }
}
