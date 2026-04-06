import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});

  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _prefsService = PrefsService();
  bool _checking = false;
  String? _errorText;

  Future<void> _submit() async {
    if (_checking) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _checking = true;
      _errorText = null;
    });

    final savedPassword = await _prefsService.getAdminPassword();
    final typed = _passwordController.text.trim();

    if (!mounted) {
      return;
    }

    if (typed == savedPassword) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _checking = false;
      _errorText = 'Sai mật khẩu';
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu admin',
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submit,
                child: Text(_checking ? 'ĐANG KIỂM TRA...' : 'XÁC NHẬN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
