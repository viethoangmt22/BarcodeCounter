import 'package:flutter/material.dart';

import '../models/scan_config.dart';
import '../services/prefs_service.dart';
import 'scanner_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _masterController = TextEditingController();
  final _bagController = TextEditingController(text: '10');
  final _boxController = TextEditingController(text: '100');
  final _prefsService = PrefsService();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final master = await _prefsService.getMasterCode();
    final bag = await _prefsService.getBagTarget();
    final box = await _prefsService.getBoxTarget();

    if (!mounted) {
      return;
    }

    setState(() {
      _masterController.text = master;
      _bagController.text = bag.toString();
      _boxController.text = box.toString();
      _loading = false;
    });
  }

  Future<void> _startScanning() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final masterCode = _masterController.text.trim();
    final bagTarget = int.parse(_bagController.text.trim());
    final boxTarget = int.parse(_boxController.text.trim());

    await _prefsService.saveSetup(
      masterCode: masterCode,
      bagTarget: bagTarget,
      boxTarget: boxTarget,
    );

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScannerScreen(
          config: ScanConfig(
            masterCode: masterCode,
            bagTarget: bagTarget,
            boxTarget: boxTarget,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _masterController.dispose();
    _bagController.dispose();
    _boxController.dispose();
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
                      controller: _bagController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'SL1 (bag target)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final parsed = int.tryParse(value?.trim() ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'SL1 phai la so > 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _boxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'SL2 (box target)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final parsed = int.tryParse(value?.trim() ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'SL2 phai la so > 0';
                        }
                        return null;
                      },
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _startScanning,
                      child: const Text('START'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
