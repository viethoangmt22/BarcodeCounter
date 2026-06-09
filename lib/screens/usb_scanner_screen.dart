import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/scan_config.dart';
import '../providers/usb_scanner_provider.dart';
import '../services/tts_service.dart';
import '../widgets/hold_to_reset_button.dart';

class UsbScannerScreen extends StatelessWidget {
  const UsbScannerScreen({required this.config, super.key});

  final ScanConfig config;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UsbScannerProvider>(
      create: (_) => UsbScannerProvider(
        config: config,
        ttsService: TtsService(),
      ),
      child: const _UsbScannerView(),
    );
  }
}

class _UsbScannerView extends StatefulWidget {
  const _UsbScannerView();

  @override
  State<_UsbScannerView> createState() => _UsbScannerViewState();
}

class _UsbScannerViewState extends State<_UsbScannerView>
    with SingleTickerProviderStateMixin {
  String _buffer = '';
  DateTime _lastEventTime = DateTime.now();
  late AnimationController _ngAnimationController;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    _ngAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _ngAnimationController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final provider = context.read<UsbScannerProvider>();
    if (!provider.scanningActive || provider.ngLocked) {
      return false;
    }

    final now = DateTime.now();
    if (now.difference(_lastEventTime) > const Duration(seconds: 1)) {
      _buffer = '';
    }
    _lastEventTime = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.trim();
      _buffer = '';
      if (code.isNotEmpty) {
        provider.handleBarcodeScanned(code);
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsbScannerProvider>();
    final theme = Theme.of(context);

    // Trigger pulse animation when NG is locked
    if (provider.ngLocked) {
      _ngAnimationController.repeat(reverse: true);
    } else {
      _ngAnimationController.stop();
    }

    final Color primaryProductColor = provider.config.colorValue != null
        ? Color(provider.config.colorValue!)
        : theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Đếm Sản Phẩm (USB HID)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          if (provider.config.colorValue != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: primaryProductColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status bar (OK / NG / Scanning)
            _buildStatusBar(provider),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Product Information Header
                    _buildProductHeader(provider, primaryProductColor),
                    const SizedBox(height: 16),

                    // Counters Grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildCounterTile(
                            title: 'SỐ LƯỢNG OK',
                            value: provider.totalValidCount.toString(),
                            subtitle: provider.config.requiresTwoCodes
                                ? 'Mục tiêu túi: ${provider.config.bagTarget}'
                                : null,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCounterTile(
                            title: 'SỐ LƯỢNG NG',
                            value: provider.totalInvalidCount.toString(),
                            subtitle: 'Lỗi sai mã sản phẩm',
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dual barcode buffer tracker (Visual slot indicators)
                    if (provider.config.requiresTwoCodes) ...[
                      _buildDualBarcodeTracker(provider),
                      const SizedBox(height: 16),
                    ],

                    // Details Card
                    _buildDetailsCard(provider),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom Buttons Bar
            _buildBottomButtons(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(UsbScannerProvider provider) {
    if (provider.ngLocked) {
      return AnimatedBuilder(
        animation: _ngAnimationController,
        builder: (context, child) {
          final opacity = 0.6 + (_ngAnimationController.value * 0.4);
          return Container(
            color: Colors.red.withOpacity(opacity),
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 36),
                SizedBox(height: 4),
                Text(
                  'NG - KHÓA BÁO SAI MÃ SẢN PHẨM!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kiểm tra lại sản phẩm và bấm TIẾP TỤC để quét tiếp',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          );
        },
      );
    }

    if (provider.status == UsbScanStatus.ok) {
      return Container(
        color: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text(
              'QUÉT THÀNH CÔNG (OK)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.blue.shade700,
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'USB HID ĐANG LẮNG NGHE ĐẦU ĐỌC...',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductHeader(UsbScannerProvider provider, Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: themeColor),
              const SizedBox(width: 8),
              Text(
                'SẢN PHẨM ĐANG QUÉT',
                style: TextStyle(
                  color: themeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            provider.config.productName ?? 'Không tên',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterTile({
    required String title,
    required String value,
    String? subtitle,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color.shade800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: color.shade900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDualBarcodeTracker(UsbScannerProvider provider) {
    final codes = provider.config.requiredCodes;
    if (codes.length < 2) return const SizedBox.shrink();

    final code1 = codes[0];
    final code2 = codes[1];

    final has1 = provider.scannedCodesBuffer.contains(code1);
    final has2 = provider.scannedCodesBuffer.contains(code2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TIẾN TRÌNH QUÉT ĐÔI (2 MÃ YÊU CẦU):',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildBarcodeSlot(1, code1, has1)),
              const SizedBox(width: 12),
              Expanded(child: _buildBarcodeSlot(2, code2, has2)),
            ],
          ),
          if (provider.scannedCodesBuffer.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tự động reset bộ đệm sau 5 giây không quét...',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarcodeSlot(int index, String code, bool isScanned) {
    final color = isScanned ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isScanned ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isScanned ? Colors.green.shade300 : Colors.grey.shade300,
          width: 1.5,
          style: isScanned ? BorderStyle.solid : BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
            ),
            child: Icon(
              isScanned ? Icons.check : Icons.hourglass_empty,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mã yêu cầu $index',
                  style: TextStyle(
                    fontSize: 11,
                    color: isScanned ? Colors.green.shade900 : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  code,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isScanned ? Colors.green.shade800 : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(UsbScannerProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            icon: Icons.qr_code,
            title: 'Mã vừa quét',
            value: provider.lastScannedCode,
            valueColor: Colors.blue.shade900,
            valueBold: true,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            icon: Icons.checklist,
            title: 'Mã đăng ký yêu cầu',
            value: provider.config.requiredCodes.join(' + '),
            valueBold: true,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            icon: Icons.assignment_outlined,
            title: 'Các mốc báo đóng bao/thùng',
            value: provider.config.alertLevels
                .map((l) => '${l.quantity}: ${l.message}')
                .join('\n'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: valueBold ? FontWeight.bold : FontWeight.normal,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons(UsbScannerProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // RESUME Button (Active when locked)
          Expanded(
            child: FilledButton.tonal(
              onPressed: provider.ngLocked ? provider.resumeAfterNg : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: provider.ngLocked ? Colors.green.shade100 : null,
                foregroundColor: provider.ngLocked ? Colors.green.shade900 : null,
              ),
              child: const Text(
                'TIẾP TỤC',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // HOLD TO RESET Button
          Expanded(
            child: HoldToResetButton(
              onReset: provider.resetCounters,
            ),
          ),
          const SizedBox(width: 8),

          // STOP Button (Pop and close)
          Expanded(
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.grey.shade800,
              ),
              child: const Text(
                'DỪNG',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
