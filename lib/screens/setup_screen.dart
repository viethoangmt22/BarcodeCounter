import 'package:flutter/material.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
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
  final _masterController = TextEditingController();
  final _okMessageController = TextEditingController();
  final _ngMessageController = TextEditingController();
  final _prefsService = PrefsService();
  final List<_AlertLevelDraft> _levelDrafts = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final config = await _prefsService.getScanConfig();

    if (!mounted) {
      return;
    }

    setState(() {
      _masterController.text = config.masterCode;
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

    final masterCode = _masterController.text.trim();
    final okMessage = _okMessageController.text.trim();
    final ngMessage = _ngMessageController.text.trim();

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

    final config = ScanConfig(
      masterCode: masterCode,
      okMessage: okMessage,
      ngMessage: ngMessage,
      alertLevels: levels,
    );

    await _prefsService.saveSetup(config);

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScannerScreen(config: config)),
    );
  }

  @override
  void dispose() {
    _masterController.dispose();
    _okMessageController.dispose();
    _ngMessageController.dispose();
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
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _masterController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Master Barcode',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui long nhap master barcode';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _okMessageController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Âm thanh khi quét đúng (OK)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập nội dung âm thanh OK';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ngMessageController,
                      decoration: const InputDecoration(
                        labelText: 'Âm thanh khi quét sai (NG)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập nội dung âm thanh NG';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _levelDrafts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final level = _levelDrafts[index];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Mốc SL${index + 1}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                    ),
                                    if (_levelDrafts.length > 2)
                                      IconButton(
                                        onPressed: () {
                                          setState(() {
                                            final removed = _levelDrafts
                                                .removeAt(index);
                                            removed.dispose();
                                          });
                                        },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                  ],
                                ),
                                TextFormField(
                                  controller: level.quantityController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Số lượng (ví dụ 10, 100, 500)',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final parsed = int.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    if (parsed == null || parsed <= 0) {
                                      return 'Số lượng phải là số > 0';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: level.messageController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nội dung âm thanh cảnh báo',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Vui lòng nhập nội dung cảnh báo';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(_addAlertLevel);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm mốc SL3/SL4...'),
                    ),
                    FilledButton(
                      onPressed: _startScanning,
                      child: const Text('BẮT ĐẦU'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
