import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
import '../services/scanner_utils.dart';
import 'scanner_screen.dart';

class _AlertLevelDraft {
  _AlertLevelDraft({
    required this.quantityController,
    required this.messageController,
  });

  final TextEditingController quantityController;
  final TextEditingController messageController;

  void dispose() {
    quantityController.dispose();
    messageController.dispose();
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _barcode1Controller = TextEditingController();
  final _barcode2Controller = TextEditingController();
  final _okMessageController = TextEditingController();
  final _ngMessageController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _prefsService = PrefsService();
  final List<_AlertLevelDraft> _levelDrafts = [];
  final List<ScanPreset> _presets = [];

  bool _loading = true;
  int _requiredBarcodeCount = 1;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final config = await _prefsService.getScanConfig();
    final presets = await _prefsService.getPresets();

    if (!mounted) {
      return;
    }

    setState(() {
      _presets
        ..clear()
        ..addAll(presets);
      final requiredCodes = config.requiredCodes;
      _requiredBarcodeCount = requiredCodes.length >= 2 ? 2 : 1;
      _barcode1Controller.text = requiredCodes.isNotEmpty
          ? requiredCodes[0]
          : '';
      _barcode2Controller.text = requiredCodes.length >= 2
          ? requiredCodes[1]
          : '';
      _okMessageController.text = config.okMessage;
      _ngMessageController.text = config.ngMessage;
      _levelDrafts
        ..clear()
        ..addAll(
          config.alertLevels.map(
            (level) => _AlertLevelDraft(
              quantityController: TextEditingController(
                text: level.quantity.toString(),
              ),
              messageController: TextEditingController(text: level.message),
            ),
          ),
        );

      if (_levelDrafts.isEmpty) {
        _addAlertLevel();
        _addAlertLevel();
      }

      _loading = false;
    });
  }

  void _applyPresetToForm(ScanPreset preset) {
    setState(() {
      final codes = preset.requiredCodes;
      _requiredBarcodeCount = codes.length >= 2 ? 2 : 1;
      _barcode1Controller.text = codes.isNotEmpty ? codes[0] : '';
      _barcode2Controller.text = codes.length >= 2 ? codes[1] : '';
      _okMessageController.text = preset.config.okMessage;
      _ngMessageController.text = preset.config.ngMessage;

      for (final draft in _levelDrafts) {
        draft.dispose();
      }
      _levelDrafts
        ..clear()
        ..addAll(
          preset.config.alertLevels.map(
            (level) => _AlertLevelDraft(
              quantityController: TextEditingController(
                text: level.quantity.toString(),
              ),
              messageController: TextEditingController(text: level.message),
            ),
          ),
        );

      if (_levelDrafts.isEmpty) {
        _addAlertLevel();
        _addAlertLevel();
      }
    });
  }

  Future<void> _deletePreset(ScanPreset preset) async {
    await _prefsService.deletePresetByRequiredCodes(preset.requiredCodes);
    final presets = await _prefsService.getPresets();
    if (!mounted) {
      return;
    }
    setState(() {
      _presets
        ..clear()
        ..addAll(presets);
    });
  }

  void _addAlertLevel() {
    final index = _levelDrafts.length + 1;
    final defaultQty = index == 1
        ? 10
        : index == 2
        ? 100
        : index * 100;
    final defaultMessage = index == 1
        ? 'Đủ 10 cái rồi đóng túi nilon đi'
        : index == 2
        ? 'Đủ 100 cái rồi đóng thùng đi'
        : 'Đủ $defaultQty cái rồi xử lý mốc SL$index';

    _levelDrafts.add(
      _AlertLevelDraft(
        quantityController: TextEditingController(text: defaultQty.toString()),
        messageController: TextEditingController(text: defaultMessage),
      ),
    );
  }

  Future<void> _startScanning() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final config = _buildConfigFromInputs();

    final newAdminPassword = _adminPasswordController.text.trim();
    if (newAdminPassword.isNotEmpty) {
      await _prefsService.setAdminPassword(newAdminPassword);
    }
    await _prefsService.saveSetup(config);

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScannerScreen(config: config)),
    );
  }

  ScanConfig _buildConfigFromInputs() {
    final barcode1 = _barcode1Controller.text.trim();
    final barcode2 = _barcode2Controller.text.trim();
    final okMessage = _okMessageController.text.trim();
    final ngMessage = _ngMessageController.text.trim();
    final requiredCodes = _requiredBarcodeCount == 2
        ? <String>[barcode1, barcode2]
        : <String>[barcode1];

    final levels =
        _levelDrafts
            .map(
              (draft) => ScanAlertLevel(
                quantity: int.parse(draft.quantityController.text.trim()),
                message: draft.messageController.text.trim(),
              ),
            )
            .toList()
          ..sort((a, b) => a.quantity.compareTo(b.quantity));

    return ScanConfig(
      requiredCodes: requiredCodes,
      okMessage: okMessage,
      ngMessage: ngMessage,
      alertLevels: levels,
    );
  }

  String? _validateEan13(String? value, {required String emptyMessage}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return emptyMessage;
    }

    if (!RegExp(r'^\d{13}$').hasMatch(text)) {
      return 'Barcode phải là EAN-13 (13 chữ số)';
    }

    return null;
  }

  Future<void> _scanAndFillCodes(int count) async {
    final scannedCodes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => _RegisterBarcodeScreen(requiredCount: count),
      ),
    );

    if (!mounted || scannedCodes == null || scannedCodes.isEmpty) {
      return;
    }

    setState(() {
      _barcode1Controller.text = scannedCodes.first.trim();
      if (count == 2) {
        _barcode2Controller.text = scannedCodes.length > 1
            ? scannedCodes[1].trim()
            : '';
      }
    });
  }

  Future<void> _savePreset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final config = _buildConfigFromInputs();
    await _prefsService.savePreset(
      ScanPreset(requiredCodes: config.requiredCodes, config: config),
    );

    final presets = await _prefsService.getPresets();

    if (!mounted) {
      return;
    }

    setState(() {
      _presets
        ..clear()
        ..addAll(presets);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu preset')));
  }

  @override
  void dispose() {
    _barcode1Controller.dispose();
    _barcode2Controller.dispose();
    _okMessageController.dispose();
    _ngMessageController.dispose();
    _adminPasswordController.dispose();
    for (final draft in _levelDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode Setup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Divider(height: 32),
                  Text(
                    'Preset da luu (Library)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_presets.isEmpty)
                    Text(
                      'Chua co preset',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ..._presets.map(
                      (preset) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            color: Colors.blueGrey.shade50.withOpacity(0.3),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      preset.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    preset.requiredCodes.length == 2
                                        ? 'Dual'
                                        : 'Single',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Milestones: ${preset.config.alertLevels.map((l) => l.quantity).join(', ')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'OK Sound: ${preset.config.okMessage}',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _applyPresetToForm(preset),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      label: const Text('Nap preset'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => _deletePreset(preset),
                                      style: FilledButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                      ),
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                      label: const Text('Xoa'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'CAU HÌNH PRESET DANG CHON',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '1. Barcode can quet',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('1 barcode'),
                            ),
                            ButtonSegment<int>(
                              value: 2,
                              label: Text('2 barcode'),
                            ),
                          ],
                          selected: <int>{_requiredBarcodeCount},
                          onSelectionChanged: (selection) {
                            final selected = selection.first;
                            setState(() {
                              _requiredBarcodeCount = selected;
                              if (_requiredBarcodeCount == 1) {
                                _barcode2Controller.clear();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _barcode1Controller,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Barcode 1 (EAN-13)',
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                validator: (value) => _validateEan13(
                                  value,
                                  emptyMessage: 'Vui lòng nhập barcode 1',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_requiredBarcodeCount == 1)
                              IconButton.filledTonal(
                                onPressed: () => _scanAndFillCodes(1),
                                icon: const Icon(Icons.qr_code_scanner),
                                tooltip: 'Quét từ camera',
                              ),
                          ],
                        ),
                        if (_requiredBarcodeCount == 2) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _barcode2Controller,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Barcode 2 (EAN-13)',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (value) {
                                    final error = _validateEan13(
                                      value,
                                      emptyMessage: 'Vui lòng nhập barcode 2',
                                    );
                                    if (error != null) {
                                      return error;
                                    }

                                    if ((value?.trim() ?? '') ==
                                        _barcode1Controller.text.trim()) {
                                      return 'Barcode 2 phải khác barcode 1';
                                    }

                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _scanAndFillCodes(2),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Quét 2 mã mẫu'),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '2. Moc so luong',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(_addAlertLevel);
                              },
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              label: const Text('Them'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ...List.generate(_levelDrafts.length, (index) {
                          final level = _levelDrafts[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.blue.shade100,
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Mốc SL${index + 1}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      ),
                                      if (_levelDrafts.length > 1)
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              final removed =
                                                  _levelDrafts.removeAt(index);
                                              removed.dispose();
                                            });
                                          },
                                          icon: const Icon(Icons.remove_circle_outline,
                                              size: 20, color: Colors.red),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: level.quantityController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Số lượng (ví dụ 10, 100)',
                                      isDense: true,
                                      border: UnderlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      final parsed = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (parsed == null || parsed <= 0) {
                                        return 'Phải là số > 0';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: level.messageController,
                                    decoration: const InputDecoration(
                                      labelText: 'Cảnh báo âm thanh',
                                      isDense: true,
                                      border: UnderlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Vui lòng nhập âm thanh';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        Text(
                          '3. Am thanh khac',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _okMessageController,
                          decoration: const InputDecoration(
                            labelText: 'Âm thanh quét đúng (OK)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ngMessageController,
                          decoration: const InputDecoration(
                            labelText: 'Âm thanh quét sai (NG)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _savePreset,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          icon: const Icon(Icons.save),
                          label: const Text('LUU VAO PRESET LIBRARY'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Admin Security',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _adminPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Đổi mật khẩu admin',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _startScanning,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'BẮT ĐẦU VỚI CẤU HÌNH TRÊN',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _RegisterBarcodeScreen extends StatefulWidget {
  const _RegisterBarcodeScreen({required this.requiredCount});

  final int requiredCount;

  @override
  State<_RegisterBarcodeScreen> createState() => _RegisterBarcodeScreenState();
}

class _RegisterBarcodeScreenState extends State<_RegisterBarcodeScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: ScannerUtils.detectionSpeed,
    detectionTimeoutMs: ScannerUtils.detectionTimeoutMs,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  bool _captured = false;
  final List<String> _capturedCodes = [];
  bool _torchOn = false;
  String? _candidateKey;
  int _candidateHits = 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_captured) {
      return;
    }

    final detected = ScannerUtils.pickDetectedCodes(capture);
    if (detected.isEmpty) {
      return;
    }

    final key = detected.join('|');
    if (_candidateKey == key) {
      _candidateHits++;
    } else {
      _candidateKey = key;
      _candidateHits = 1;
    }

    if (_candidateHits < 2) {
      return;
    }

    _candidateHits = 0;

    for (final code in detected) {
      if (!_capturedCodes.contains(code)) {
        _capturedCodes.add(code);
      }
    }

    if (_capturedCodes.length < widget.requiredCount) {
      return;
    }

    _captured = true;
    await _controller.stop();

    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pop(_capturedCodes.take(widget.requiredCount).toList());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã để đăng ký'),
        actions: [
          IconButton(
            onPressed: () async {
              await _controller.toggleTorch();
              if (!mounted) {
                return;
              }
              setState(() {
                _torchOn = !_torchOn;
              });
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.requiredCount == 2
                    ? 'Đưa cả 2 mã vào khung camera. Hệ thống sẽ tự điền sau khi quét đủ 2 mã.'
                    : 'Đưa mã vào khung camera. Hệ thống sẽ tự điền mã sau khi quét thành công.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
