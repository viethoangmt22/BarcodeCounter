import 'package:flutter/material.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
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
  int _presetSampleCount = 1;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
    });

    final config = await _prefsService.getScanConfig();
    if (!mounted) {
      return;
    }

    setState(() {
      _config = config;
      _activePresetName = null;
      _loading = false;
    });
  }

  Future<void> _openAdmin() async {
    final unlocked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AdminGateScreen()),
    );

    if (!mounted) {
      return;
    }

    if (unlocked == true) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
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
  }

  Future<void> _scanPresetSample() async {
    final sampleCodes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => PresetScanScreen(requiredCount: _presetSampleCount),
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

    setState(() {
      _config = preset.config;
      _activePresetName = preset.name;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã nạp preset: ${preset.name}')));
  }

  @override
  Widget build(BuildContext context) {
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
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InfoCard(
                    title: 'Barcode đã đăng ký',
                    value: _config == null || _config!.requiredCodes.isEmpty
                        ? 'Chưa đăng ký'
                        : _config!.requiredCodes.join(' + '),
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'Preset đang dùng',
                    value:
                        _activePresetName ??
                        (_config == null || _config!.requiredCodes.isEmpty
                            ? 'Chưa chọn preset'
                            : _config!.requiredCodes.join(' + ')),
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'Trạng thái',
                    value: _config == null || _config!.requiredCodes.isEmpty
                        ? 'Cần admin đăng ký barcode'
                        : 'Sẵn sàng quét',
                  ),
                  const Spacer(),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('Quet 1 barcode'),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        label: Text('Quet 2 barcode'),
                      ),
                    ],
                    selected: <int>{_presetSampleCount},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _presetSampleCount = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _scanPresetSample,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('QUÉT MÃ MẪU (LOAD PRESET)'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _config == null || _config!.requiredCodes.isEmpty
                        ? null
                        : _startScanning,
                    child: const Text('BẮT ĐẦU QUÉT'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
