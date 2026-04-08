import 'dart:async';
import 'package:flutter/material.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
import '../widgets/hold_to_reset_button.dart';
import 'admin_gate_screen.dart';
import 'preset_scan_screen.dart';
import 'scanner_screen.dart';
import 'setup_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _prefsService = PrefsService();
  bool _loading = true;
  ScanConfig? _config;
  String? _activePresetName;
  int _currentOk = 0;
  int _currentNg = 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      setState(() {
        _loading = true;
      });

      final lastUsed = await _prefsService.getLastUsedPreset();

      if (!mounted) {
        return;
      }

      if (lastUsed != null) {
        final counts =
            await _prefsService.getPresetCounts(lastUsed.config.signature);
        setState(() {
          _config = lastUsed.config;
          _activePresetName = lastUsed.name;
          _currentOk = counts['ok'] ?? 0;
          _currentNg = counts['ng'] ?? 0;
          _loading = false;
        });
        return;
      }

      final config = await _prefsService.getScanConfig();
      final counts = await _prefsService.getPresetCounts(config.signature);
      if (!mounted) {
        return;
      }

      setState(() {
        _config = config;
        _activePresetName = null;
        _currentOk = counts['ok'] ?? 0;
        _currentNg = counts['ng'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading config: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openAdmin() async {
    final unlocked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AdminGateScreen()),
    );

    if (!mounted) {
      return;
    }

    if (unlocked == true) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
      await _loadConfig();
    }
  }

  Future<void> _startScanning() async {
    final config = _config;
    if (config == null || config.requiredCodes.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScannerScreen(config: config)),
    );
    await _loadConfig(); // Refresh counts when back
  }

  Future<void> _scanPresetSample() async {
    final sampleCodes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => const PresetScanScreen(),
      ),
    );

    if (!mounted || sampleCodes == null || sampleCodes.isEmpty) {
      return;
    }

    final preset = await _prefsService.findPresetByRequiredCodes(sampleCodes);
    if (!mounted) {
      return;
    }

    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy preset cho mã mẫu này')),
      );
      return;
    }

    final isNewCode = _config == null || preset.config.signature != _config!.signature;
    
    int ok = 0;
    int ng = 0;
    
    if (isNewCode) {
      // Mã mới: reset về 0
      await _prefsService.savePresetCounts(preset.config.signature, 0, 0);
    } else {
      // Trùng mã: tiếp tục phiên làm việc (load counts hiện tại)
      final counts = await _prefsService.getPresetCounts(preset.config.signature);
      ok = counts['ok'] ?? 0;
      ng = counts['ng'] ?? 0;
    }

    setState(() {
      _config = preset.config;
      _activePresetName = preset.name;
      _currentOk = ok;
      _currentNg = ng;
    });

    unawaited(_prefsService.saveLastUsedPreset(preset));

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Đã nạp preset: ${preset.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = _config != null && _config!.requiredCodes.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Counter'),
        actions: [
          IconButton(
            onPressed: _openAdmin,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Enlarged Preset Card
                  _PresetDetailsCard(
                    config: _config,
                    activePresetName: _activePresetName,
                    currentOk: _currentOk,
                    currentNg: _currentNg,
                    onReset: () async {
                      if (_config != null) {
                        unawaited(_prefsService.savePresetCounts(
                            _config!.signature, 0, 0));
                        setState(() {
                          _currentOk = 0;
                          _currentNg = 0;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Status Card with colors
                  _StatusCard(
                    isReady: hasConfig,
                    message: hasConfig
                        ? 'Sẵn sàng quét'
                        : 'Chưa sẵn sàng (Cần nạp mã mẫu)',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : Container(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _scanPresetSample,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('QUÉT MÃ MẪU (LOAD PRESET)'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: !hasConfig ? null : _startScanning,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    child: const Text('BẮT ĐẦU QUÉT'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PresetDetailsCard extends StatelessWidget {
  const _PresetDetailsCard({
    this.config,
    this.activePresetName,
    this.currentOk = 0,
    this.currentNg = 0,
    this.onReset,
  });

  final ScanConfig? config;
  final String? activePresetName;
  final int currentOk;
  final int currentNg;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasConfig = config != null && config!.requiredCodes.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'PRESET ĐANG DÙNG',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (config?.colorValue != null)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Color(config!.colorValue!),
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
            ],
          ),
          const SizedBox(height: 16),
          Text(
            activePresetName ??
                (hasConfig ? (config!.productName ?? 'Tên n/a') : 'Chưa chọn preset'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: hasConfig ? Colors.black87 : Colors.grey.shade500,
            ),
          ),
          if (hasConfig) ...[
            const SizedBox(height: 8),
            Text(
              'Mã: ${config!.requiredCodes.join(' + ')}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Số lượng OK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '$currentOk',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Số lượng NG',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '$currentNg',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onReset != null) ...[
              const SizedBox(height: 16),
              HoldToResetButton(onReset: onReset!),
            ],
            const Divider(height: 32),
            Text(
              'CÁC MỐC CẢNH BÁO:',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            ...config!.alertLevels.map(
              (level) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        '${level.quantity}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          level.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.3,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Vui lòng quét mã mẫu để nạp cấu hình',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isReady, required this.message});

  final bool isReady;
  final String message;

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = isReady ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReady ? Icons.check_circle : Icons.error,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRẠNG THÁI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color.withOpacity(0.7),
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

