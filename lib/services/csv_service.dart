import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../models/scan_config.dart';

class CsvService {
  static const Map<String, int> _nameToColor = {
    'Đỏ': 0xFFF44336, // Colors.red
    'Cam': 0xFFFF9800, // Colors.orange
    'Vàng': 0xFFFFC107, // Colors.amber
    'Xanh lá': 0xFF4CAF50, // Colors.green
    'Xanh ngọc': 0xFF009688, // Colors.teal
    'Xanh dương': 0xFF2196F3, // Colors.blue
    'Xanh chàm': 0xFF3F51B5, // Colors.indigo
    'Tím': 0xFF9C27B0, // Colors.purple
    'Hồng': 0xFFE91E63, // Colors.pink
    'Nâu': 0xFF795548, // Colors.brown
  };

  static const Map<int, String> _colorToName = {
    0xFFF44336: 'Đỏ',
    0xFFFF9800: 'Cam',
    0xFFFFC107: 'Vàng',
    0xFF4CAF50: 'Xanh lá',
    0xFF009688: 'Xanh ngọc',
    0xFF2196F3: 'Xanh dương',
    0xFF3F51B5: 'Xanh chàm',
    0xFF9C27B0: 'Tím',
    0xFFE91E63: 'Hồng',
    0xFF795548: 'Nâu',
  };

  /// Exports presets to CSV and shares the file.
  Future<void> exportPresets(List<ScanPreset> presets) async {
    final List<List<dynamic>> rows = [
      [
        'Product Name',
        'Barcode 1',
        'Barcode 2',
        'OK Message',
        'NG Message',
        'Color',
        'Alert Levels'
      ]
    ];

    for (final preset in presets) {
      // Prepend a Tab character to force Excel to treat numbers as text
      final String barcode1 =
          preset.requiredCodes.isNotEmpty ? '\t${preset.requiredCodes[0]}' : '';
      final String barcode2 =
          preset.requiredCodes.length > 1 ? '\t${preset.requiredCodes[1]}' : '';

      final String alertLevelsStr = preset.config.alertLevels
          .map((l) => '${l.quantity}:${l.message}')
          .join(';');

      final String colorName = _colorToName[preset.config.colorValue] ?? '';

      rows.add([
        preset.config.productName ?? '',
        barcode1,
        barcode2,
        preset.config.okMessage,
        preset.config.ngMessage,
        colorName,
        alertLevelsStr,
      ]);
    }

    // Add UTF-8 BOM (\uFEFF) to tell Excel to open the file in UTF-8 encoding
    final String csvData = '\uFEFF${const ListToCsvConverter().convert(rows)}';
    final Directory directory = await getTemporaryDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'barcode_presets_export_$timestamp.csv';
    final String path = '${directory.path}/$fileName';
    final File file = File(path);
    await file.writeAsString(csvData, encoding: utf8);

    final params = SaveFileDialogParams(sourceFilePath: path);
    await FlutterFileDialog.saveFile(params: params);
  }

  /// Picks a CSV file and parses it into ScanPresets.
  Future<List<ScanPreset>?> importPresets() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    final File file = File(result.files.single.path!);
    final String content = await file.readAsString(encoding: utf8);
    final List<List<dynamic>> rows =
        const CsvToListConverter(shouldParseNumbers: false).convert(content);

    if (rows.isEmpty) return [];

    final List<ScanPreset> presets = [];
    // Start from index 1 to skip header
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 5) continue; // Basic validation

      final String productName = row[0].toString().trim();
      // .trim() will remove any leading Tab \t characters added by export
      final String barcode1 = row[1].toString().trim();
      final String barcode2 = row.length > 2 ? row[2].toString().trim() : '';
      final String okMsg = row.length > 3 ? row[3].toString().trim() : 'OK';
      final String ngMsg = row.length > 4 ? row[4].toString().trim() : 'SAI';
      final String colorName = row.length > 5 ? row[5].toString().trim() : '';
      final String alertLevelsStr = row.length > 6 ? row[6].toString().trim() : '';

      if (barcode1.isEmpty) continue;

      final List<String> requiredCodes =
          barcode2.isNotEmpty ? [barcode1, barcode2] : [barcode1];

      final List<ScanAlertLevel> alertLevels = [];
      if (alertLevelsStr.isNotEmpty) {
        final parts = alertLevelsStr.split(';');
        for (final part in parts) {
          final subParts = part.split(':');
          if (subParts.length == 2) {
            final int? qty = int.tryParse(subParts[0].trim());
            if (qty != null) {
              alertLevels.add(ScanAlertLevel(
                quantity: qty,
                message: subParts[1].trim(),
              ));
            }
          }
        }
      }

      // Default alert levels if empty
      if (alertLevels.isEmpty) {
        alertLevels.add(const ScanAlertLevel(quantity: 10, message: 'Đủ 10 túi'));
        alertLevels.add(const ScanAlertLevel(quantity: 100, message: 'Đủ 100 thùng'));
      }

      final int? colorValue = _nameToColor[colorName];

      presets.add(ScanPreset(
        requiredCodes: requiredCodes,
        config: ScanConfig(
          requiredCodes: requiredCodes,
          okMessage: okMsg,
          ngMessage: ngMsg,
          alertLevels: alertLevels,
          productName: productName,
          colorValue: colorValue,
        ),
      ));
    }

    return presets;
  }

  /// Appends a single scan record to the daily CSV log.
  /// Filename: scans_YYYY-MM-DD.csv
  Future<void> appendScanLog({
    required String barcode,
    required String status,
    required int count,
    String? instruction,
  }) async {
    final now = DateTime.now();
    final String dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final String timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    final Directory docDir = await getApplicationDocumentsDirectory();
    final String fileName = 'scans_$dateStr.csv';
    final File file = File('${docDir.path}/$fileName');

    final List<dynamic> row = [
      timeStr,
      barcode,
      status,
      count,
      instruction ?? '',
    ];

    final String csvRow = const ListToCsvConverter().convert([row]) + '\r\n';

    if (!await file.exists()) {
      // New file: write BOM + headers first
      final List<dynamic> header = [
        'Thời gian',
        'Mã barcode',
        'Trạng thái',
        'Lần quét',
        'Hướng dẫn'
      ];
      final String headerCsv = '\uFEFF' + const ListToCsvConverter().convert([header]) + '\r\n';
      await file.writeAsString(headerCsv + csvRow, encoding: utf8);
    } else {
      // Existing file: append row
      await file.writeAsString(csvRow, mode: FileMode.append, encoding: utf8);
    }
  }

  /// Lists all daily log files in the documents directory.
  Future<List<File>> listLogFiles() async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    if (!await docDir.exists()) return [];

    final List<FileSystemEntity> entities = await docDir.list().toList();
    final List<File> logs = entities
        .whereType<File>()
        .where((file) {
          final name = file.path.split(Platform.pathSeparator).last;
          return name.startsWith('scans_') && name.endsWith('.csv');
        })
        .toList();

    // Sort by name (date) descending (newest first)
    logs.sort((a, b) => b.path.compareTo(a.path));
    return logs;
  }

  /// Exports a log file to a user-chosen location.
  Future<void> exportLogFile(File file) async {
    final params = SaveFileDialogParams(sourceFilePath: file.path);
    await FlutterFileDialog.saveFile(params: params);
  }

  /// Deletes a log file.
  Future<void> deleteLogFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
