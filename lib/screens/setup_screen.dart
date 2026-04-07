import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
import '../services/scanner_utils.dart';
import '../services/csv_service.dart';
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
  final _productNameController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _prefsService = PrefsService();
  final _csvService = CsvService();
  final List<_AlertLevelDraft> _levelDrafts = [];
  final List<ScanPreset> _presets = [];

  static const List<Color> _presetColors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];

  bool _loading = true;
  bool _isEditing = false;
  int _requiredBarcodeCount = 1;
  int? _selectedColorValue;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  void _backToList() {
    setState(() {
      _isEditing = false;
    });
  }

  void _addNewConfig() {
    setState(() {
      _barcode1Controller.clear();
      _barcode2Controller.clear();
      _okMessageController.text = ScanConfig.defaults().okMessage;
      _ngMessageController.text = ScanConfig.defaults().ngMessage;
      _productNameController.clear();
      _selectedColorValue = null;
      _requiredBarcodeCount = 1;

      for (final draft in _levelDrafts) {
        draft.dispose();
      }
      _levelDrafts.clear();
      _addAlertLevel();
      _addAlertLevel();

      _isEditing = true;
    });
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
      _productNameController.text = config.productName ?? '';
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

      _selectedColorValue = config.colorValue;

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
      _productNameController.text = preset.config.productName ?? '';

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

      _selectedColorValue = preset.config.colorValue;

      if (_levelDrafts.isEmpty) {
        _addAlertLevel();
        _addAlertLevel();
      }
      _isEditing = true;
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
      colorValue: _selectedColorValue,
      productName: _productNameController.text.trim(),
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

  Future<void> _exportToCsv() async {
    try {
      await _csvService.exportPresets(_presets);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xuất file: $e')),
      );
    }
  }

  Future<void> _importFromCsv() async {
    try {
      final newPresets = await _csvService.importPresets();
      if (newPresets == null) return; // User cancelled

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xác nhận nhập dữ liệu'),
          content: Text(
              'Bạn có chắc chắn muốn nhập ${newPresets.length} sản phẩm? Thao tác này sẽ XÓA HẾT danh sách hiện tại.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ghi đè hoàn toàn'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      setState(() => _loading = true);

      // Save each one (or I could add a bulk save to PrefsService)
      // For now, let's just clear and save all
      await _prefsService.clearPresets();
      for (final p in newPresets) {
        await _prefsService.savePreset(p);
      }

      await _loadSaved();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã nhập dữ liệu thành công')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi nạp file: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _barcode1Controller.dispose();
    _barcode2Controller.dispose();
    _okMessageController.dispose();
    _ngMessageController.dispose();
    _productNameController.dispose();
    _adminPasswordController.dispose();
    for (final draft in _levelDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Barcode Setup')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isEditing) {
      return _buildListView();
    }

    return _buildEditView();
  }

  Widget _buildListView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý mã sản phẩm'),
        actions: [
          IconButton(
            onPressed: _addNewConfig,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Thêm mới',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') {
                _exportToCsv();
              } else if (value == 'import') {
                _importFromCsv();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.ios_share_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Xuất file CSV'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_open_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Nhập file CSV'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _presets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có mã sản phẩm nào được lưu',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _addNewConfig,
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm cấu hình đầu tiên'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _presets.length,
              itemBuilder: (context, index) {
                final preset = _presets[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _applyPresetToForm(preset),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (preset.config.colorValue != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(preset.config.colorValue!),
                                      border: Border.all(
                                          color: Colors.black26, width: 0.5),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    preset.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    preset.requiredCodes.length == 2
                                        ? 'Dual Code'
                                        : 'Single Code',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 16),
                            _buildInfoRow(Icons.qr_code, 'Mã barcode',
                                preset.requiredCodes.join(' + ')),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                                Icons.notification_important_outlined,
                                'Mốc số lượng',
                                preset.config.alertLevels
                                    .map((l) => '${l.quantity}')
                                    .join(' - ')),
                            const SizedBox(height: 6),
                            _buildInfoRow(Icons.volume_up_outlined, 'Âm thanh OK',
                                preset.config.okMessage,
                                maxLines: 1),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _deletePreset(preset),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
                                  label: const Text('Xóa',
                                      style: TextStyle(color: Colors.red)),
                                  style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () => _applyPresetToForm(preset),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Nạp & Chỉnh sửa'),
                                  style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text('$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEditView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình chi tiết'),
        leading: IconButton(
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                    'CẤU HÌNH PRESET ĐANG CHỌN',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '0. Tên sản phẩm (Tùy chọn)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _productNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Ví dụ: Áo thun nam, Thùng 100...',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '1. Barcode cần quét',
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
                          '2. Mốc số lượng',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(_addAlertLevel);
                        },
                        icon: const Icon(
                          Icons.add_circle_outline,
                          size: 20,
                        ),
                        label: const Text('Thêm'),
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
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Mốc SL${index + 1}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                if (_levelDrafts.length > 1)
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        final removed = _levelDrafts
                                            .removeAt(index);
                                        removed.dispose();
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20,
                                      color: Colors.red,
                                    ),
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
                    '3. Âm thanh khác',
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
                  Text(
                    '4. Màu sắc nhận diện (hiển thị khi quét)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _selectedColorValue = null),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: _selectedColorValue == null ? Colors.black : Colors.grey.shade400,
                              width: _selectedColorValue == null ? 3 : 1,
                            ),
                          ),
                          child: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ),
                      ..._presetColors.map((color) => InkWell(
                        onTap: () => setState(() => _selectedColorValue = color.value),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(
                              color: _selectedColorValue == color.value ? Colors.black : Colors.transparent,
                              width: _selectedColorValue == color.value ? 3 : 1,
                            ),
                          ),
                          child: _selectedColorValue == color.value ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _savePreset,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('LƯU VÀO PRESET LIBRARY'),
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
