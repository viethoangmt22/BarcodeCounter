import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_config.dart';

class PrefsService {
  static const _masterCodeKey = 'master_code';
  static const _okMessageKey = 'ok_message';
  static const _ngMessageKey = 'ng_message';
  static const _levelsKey = 'alert_levels';

  static const _legacyBagTargetKey = 'bag_target';
  static const _legacyBoxTargetKey = 'box_target';

  Future<String> getMasterCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_masterCodeKey) ?? '';
  }

  Future<ScanConfig> getScanConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final defaults = ScanConfig.defaults();
    final masterCode = prefs.getString(_masterCodeKey) ?? '';
    final okMessage = prefs.getString(_okMessageKey) ?? defaults.okMessage;
    final ngMessage = prefs.getString(_ngMessageKey) ?? defaults.ngMessage;

    final levelsRaw = prefs.getString(_levelsKey);
    final levels = _parseLevels(levelsRaw, prefs);

    return ScanConfig(
      masterCode: masterCode,
      okMessage: okMessage,
      ngMessage: ngMessage,
      alertLevels: levels,
    );
  }

  List<ScanAlertLevel> _parseLevels(
    String? levelsRaw,
    SharedPreferences prefs,
  ) {
    if (levelsRaw == null || levelsRaw.trim().isEmpty) {
      final legacyBag = prefs.getInt(_legacyBagTargetKey) ?? 10;
      final legacyBox = prefs.getInt(_legacyBoxTargetKey) ?? 100;
      return [
        ScanAlertLevel(
          quantity: legacyBag,
          message: 'Đủ $legacyBag cái rồi đóng túi nilon đi',
        ),
        ScanAlertLevel(
          quantity: legacyBox,
          message: 'Đủ $legacyBox cái rồi đóng thùng đi',
        ),
      ];
    }

    try {
      final decoded = jsonDecode(levelsRaw);
      if (decoded is! List) {
        return ScanConfig.defaults().alertLevels;
      }

      final parsed = decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map(ScanAlertLevel.fromJson)
          .where((level) => level.quantity > 0)
          .toList();

      if (parsed.isEmpty) {
        return ScanConfig.defaults().alertLevels;
      }

      parsed.sort((a, b) => a.quantity.compareTo(b.quantity));
      return parsed;
    } catch (_) {
      return ScanConfig.defaults().alertLevels;
    }
  }

  Future<void> saveSetup(ScanConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedLevels = [...config.alertLevels]
      ..sort((a, b) => a.quantity.compareTo(b.quantity));

    await prefs.setString(_masterCodeKey, config.masterCode);
    await prefs.setString(_okMessageKey, config.okMessage);
    await prefs.setString(_ngMessageKey, config.ngMessage);
    await prefs.setString(
      _levelsKey,
      jsonEncode(normalizedLevels.map((e) => e.toJson()).toList()),
    );
  }
}
