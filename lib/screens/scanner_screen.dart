import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/scan_config.dart';
import '../providers/scanner_provider.dart';
import '../services/tts_service.dart';
import '../widgets/hold_to_reset_button.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({required this.config, super.key});

  final ScanConfig config;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScannerProvider>(
      create: (_) =>
          ScannerProvider(config: config, ttsService: TtsService())..start(),
      child: _ScannerView(config: config),
    );
  }
}

class _ScannerView extends StatefulWidget {
  const _ScannerView({required this.config});

  final ScanConfig config;

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  double _baseZoomLevel = 0.0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Scanner'),
        actions: [
          IconButton(
            onPressed: provider.toggleTorch,
            icon: Icon(provider.torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onScaleStart: (_) {
                    _baseZoomLevel = provider.zoomLevel;
                  },
                  onScaleUpdate: (details) {
                    // Normalize zoom increment relative to 0.0-1.0 range
                    final newZoom = (_baseZoomLevel + (details.scale - 1.0) * 0.2).clamp(0.0, 1.0);
                    provider.setZoomLevel(newZoom);
                  },
                  child: MobileScanner(
                    controller: provider.scannerController,
                    fit: BoxFit.cover,
                    onDetect: provider.onDetect,
                  ),
                ),
                const _RoiOverlay(),
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ZoomButton(
                            label: '1x',
                            isActive: provider.zoomLevel == 0.0,
                            onTap: () => provider.setZoomLevel(0.0),
                          ),
                          _ZoomButton(
                            label: '1.25x',
                            isActive: provider.zoomLevel == 0.2,
                            onTap: () => provider.setZoomLevel(0.2),
                          ),
                          _ZoomButton(
                            label: '1.5x',
                            isActive: provider.zoomLevel == 0.5,
                            onTap: () => provider.setZoomLevel(0.5),
                          ),
                          _ZoomButton(
                            label: '2x',
                            isActive: provider.zoomLevel == 1.0,
                            onTap: () => provider.setZoomLevel(1.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              color: widget.config.colorValue != null ? Color(widget.config.colorValue!) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InfoTile(
                            title: 'Mã cuối',
                            value: provider.lastScannedCode,
                          ),
                          const SizedBox(height: 8),
                          _InfoTile(
                            title: 'Yêu cầu',
                            value: widget.config.requiredCodes.isEmpty
                                ? '(chưa đăng ký)'
                                : widget.config.requiredCodes.join(' + '),
                          ),
                          const SizedBox(height: 8),
                          _InfoTile(
                            title: 'Trạng thái',
                            value: provider.statusLabel,
                            valueColor: provider.statusColor,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _InfoTile(
                                  title: 'Số lượng OK',
                                  value: provider.totalValidCount.toString(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _InfoTile(
                                  title: 'Số lượng NG',
                                  value: provider.totalInvalidCount.toString(),
                                  valueColor: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: provider.ngLocked
                              ? provider.resumeAfterNg
                              : null,
                          child: const Text('TIẾP TỤC'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: HoldToResetButton(
                          onReset: provider.resetCounters,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await provider.stop();
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                          child: const Text('DỪNG'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value, this.valueColor});

  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.greenAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black87 : Colors.white,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoiOverlay extends StatelessWidget {
  const _RoiOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final roiWidth = width * 0.5;
          final roiHeight = height * 0.5;
          final left = (width - roiWidth) / 2;
          final top = (height - roiHeight) / 2;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: roiWidth,
                height: roiHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _RoiCutoutPainter(
                    Rect.fromLTWH(left, top, roiWidth, roiHeight),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoiCutoutPainter extends CustomPainter {
  _RoiCutoutPainter(this.roiRect);

  final Rect roiRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black38;
    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRect(roiRect);
    final mask = Path.combine(PathOperation.difference, fullPath, cutoutPath);
    canvas.drawPath(mask, overlayPaint);
  }

  @override
  bool shouldRepaint(covariant _RoiCutoutPainter oldDelegate) {
    return oldDelegate.roiRect != roiRect;
  }
}
