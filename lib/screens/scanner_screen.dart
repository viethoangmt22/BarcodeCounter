import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/scan_config.dart';
import '../providers/scanner_provider.dart';
import '../services/tts_service.dart';

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

class _ScannerView extends StatelessWidget {
  const _ScannerView({required this.config});

  final ScanConfig config;

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
                MobileScanner(
                  controller: provider.scannerController,
                  fit: BoxFit.cover,
                  onDetect: provider.onDetect,
                ),
                const _RoiOverlay(),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              color: config.colorValue != null ? Color(config.colorValue!) : null,
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
                            title: 'Last code',
                            value: provider.lastScannedCode,
                          ),
                          const SizedBox(height: 8),
                          _InfoTile(
                            title: 'Required',
                            value: config.requiredCodes.isEmpty
                                ? '(chua dang ky)'
                                : config.requiredCodes.join(' + '),
                          ),
                          const SizedBox(height: 8),
                          _InfoTile(
                            title: 'Status',
                            value: provider.statusLabel,
                            valueColor: provider.statusColor,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _InfoTile(
                                  title: 'OK Count',
                                  value: provider.totalValidCount.toString(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _InfoTile(
                                  title: 'NG Count',
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
                        child: OutlinedButton(
                          onPressed: provider.resetCounters,
                          child: const Text('RESET'),
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
                          child: const Text('STOP'),
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
