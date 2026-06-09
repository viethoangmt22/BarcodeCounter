import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';

class UsbPresetScanDialog extends StatefulWidget {
  const UsbPresetScanDialog({super.key});

  @override
  State<UsbPresetScanDialog> createState() => _UsbPresetScanDialogState();
}

class _UsbPresetScanDialogState extends State<UsbPresetScanDialog>
    with SingleTickerProviderStateMixin {
  final _prefsService = PrefsService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final Set<String> _scannedCodes = {};
  List<ScanPreset> _presets = [];
  String _buffer = '';
  DateTime _lastEventTime = DateTime.now();

  String? _statusMessage;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadPresets();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  Future<void> _loadPresets() async {
    final presets = await _prefsService.getPresets();
    if (mounted) {
      setState(() {
        _presets = presets;
      });
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    // Reset buffer if delay between keystrokes is more than 1 second
    if (now.difference(_lastEventTime) > const Duration(seconds: 1)) {
      _buffer = '';
    }
    _lastEventTime = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.trim();
      _buffer = '';
      if (code.isNotEmpty) {
        _onBarcodeScanned(code);
      }
      return true;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _buffer += char;
      return true;
    }
    return false;
  }

  void _onBarcodeScanned(String barcode) {
    if (_scannedCodes.contains(barcode)) {
      _showTemporaryStatus('Mã "$barcode" đã được quét trước đó.');
      return;
    }

    setState(() {
      _scannedCodes.add(barcode);
    });

    // Check if any preset is matched
    ScanPreset? bestMatch;
    for (final preset in _presets) {
      bool isSubset = true;
      for (final reqCode in preset.requiredCodes) {
        if (!_scannedCodes.contains(reqCode)) {
          isSubset = false;
          break;
        }
      }

      if (isSubset) {
        if (bestMatch == null ||
            preset.requiredCodes.length > bestMatch.requiredCodes.length) {
          bestMatch = preset;
        }
      }
    }

    if (bestMatch != null) {
      _pulseController.stop();
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      Navigator.of(context).pop(bestMatch.requiredCodes);
    } else {
      _showTemporaryStatus('Đã quét: "$barcode" (chưa đủ hoặc chưa khớp preset).');
    }
  }

  void _showTemporaryStatus(String message) {
    _statusTimer?.cancel();
    setState(() {
      _statusMessage = message;
    });
    _statusTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _pulseController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulse radar visualizer
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withOpacity(0.15),
                          ),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.usb,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ĐANG LẮNG NGHE ĐẦU ĐỌC USB',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Hướng đầu đọc USB vào mã mẫu và bấm nút quét để nạp preset tự động.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              if (_scannedCodes.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'CÁC MÃ ĐÃ NHẬN:',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _scannedCodes
                      .map((code) => Chip(
                            backgroundColor: Colors.blue.shade50,
                            label: Text(
                              code,
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: BorderSide(color: Colors.blue.shade100),
                            onDeleted: () {
                              setState(() {
                                _scannedCodes.remove(code);
                              });
                            },
                          ))
                      .toList(),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _scannedCodes.clear();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('QUÉT LẠI'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('HỦY / ĐÓNG'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
