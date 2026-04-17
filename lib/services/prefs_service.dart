import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_config.dart';

class PrefsService {
  static const _masterCodeKey = 'master_code';
  static const _requiredCodesKey = 'required_codes';
  static const _okMessageKey = 'ok_message';
  static const _ngMessageKey = 'ng_message';
  static const _levelsKey = 'alert_levels';
  static const _colorValueKey = 'color_value';
  static const _adminPasswordKey = 'admin_password';
  static const _presetsKey = 'scan_presets';
  static const _legacyBagTargetKey = 'bag_target';
  static const _legacyBoxTargetKey = 'box_target';
  static const _globalZoomKey = 'global_zoom_level';
  static const _zoomPrefix = 'zoom_';

  Future<String> getMasterCode() async {
    final config = await getScanConfig();
    return config.masterCode;
  }

  Future<ScanConfig> getScanConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final defaults = ScanConfig.defaults();
    final masterCode = prefs.getString(_masterCodeKey) ?? '';
    final requiredCodes = _parseRequiredCodes(
      prefs.getString(_requiredCodesKey),
      masterCode,
    );
    final okMessage = prefs.getString(_okMessageKey) ?? defaults.okMessage;
    final ngMessage = prefs.getString(_ngMessageKey) ?? defaults.ngMessage;

    final levelsRaw = prefs.getString(_levelsKey);
    final levels = _parseLevels(levelsRaw, prefs);
    final colorValue = prefs.getInt(_colorValueKey);

    return ScanConfig(
      requiredCodes: requiredCodes,
      okMessage: okMessage,
      ngMessage: ngMessage,
      alertLevels: levels,
      colorValue: colorValue,
    );
  }

  List<String> _parseRequiredCodes(String? raw, String fallbackMasterCode) {
    if (raw == null || raw.trim().isEmpty) {
      final normalized = fallbackMasterCode.trim();
      return normalized.isEmpty ? [] : [normalized];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        final normalized = fallbackMasterCode.trim();
        return normalized.isEmpty ? [] : [normalized];
      }

      final parsed = decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (parsed.isNotEmpty) {
        return parsed;
      }

      final normalized = fallbackMasterCode.trim();
      return normalized.isEmpty ? [] : [normalized];
    } catch (_) {
      final normalized = fallbackMasterCode.trim();
      return normalized.isEmpty ? [] : [normalized];
    }
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
    final normalizedCodes = config.requiredCodes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final normalizedLevels = [...config.alertLevels]
      ..sort((a, b) => a.quantity.compareTo(b.quantity));

    await prefs.setString(
      _masterCodeKey,
      normalizedCodes.isNotEmpty ? normalizedCodes.first : '',
    );
    await prefs.setString(_requiredCodesKey, jsonEncode(normalizedCodes));
    await prefs.setString(_okMessageKey, config.okMessage);
    await prefs.setString(_ngMessageKey, config.ngMessage);
    await prefs.setString(
      _levelsKey,
      jsonEncode(normalizedLevels.map((e) => e.toJson()).toList()),
    );
    if (config.colorValue != null) {
      await prefs.setInt(_colorValueKey, config.colorValue!);
    } else {
      await prefs.remove(_colorValueKey);
    }
  }

  Future<String> getAdminPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminPasswordKey) ?? '1234';
  }

  Future<void> setAdminPassword(String newPassword) async {
    final normalized = newPassword.trim();
    if (normalized.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminPasswordKey, normalized);
  }

  Future<List<ScanPreset>> getPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map(ScanPreset.fromJson)
          .where(
            (preset) =>
                preset.requiredCodes.isNotEmpty &&
                preset.config.requiredCodes.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePreset(ScanPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = await getPresets();
    final normalizedCodes = preset.requiredCodes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalizedCodes.isEmpty) {
      return;
    }

    final signature = _signatureForCodes(normalizedCodes);

    final updated = <ScanPreset>[
      ...presets.where((item) => item.signature != signature),
      ScanPreset(requiredCodes: normalizedCodes, config: preset.config),
    ];

    await prefs.setString(
      _presetsKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  Future<ScanPreset?> findPresetBySampleCode(String sampleCode) async {
    final normalized = sampleCode.trim();
    if (normalized.isEmpty) {
      return null;
    }

    return findPresetByRequiredCodes([normalized]);
  }

  Future<ScanPreset?> findPresetByRequiredCodes(
    Iterable<String> requiredCodes,
  ) async {
    final normalizedCodes = requiredCodes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalizedCodes.isEmpty) {
      return null;
    }

    final signature = _signatureForCodes(normalizedCodes);
    final presets = await getPresets();
    for (final preset in presets) {
      if (preset.signature == signature) {
        return preset;
      }
    }
    return null;
  }

  Future<void> deletePresetByRequiredCodes(
    Iterable<String> requiredCodes,
  ) async {
    final normalizedCodes = requiredCodes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (normalizedCodes.isEmpty) {
      return;
    }

    final signature = _signatureForCodes(normalizedCodes);
    final presets = await getPresets();
    final updated = presets.where((preset) => preset.signature != signature);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _presetsKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_presetsKey);
  }

  static const _lastUsedPresetGlobalKey = 'last_used_preset_global';
  static const _countsPrefix = 'counts_';

  Future<void> saveLastUsedPreset(ScanPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsedPresetGlobalKey, preset.signature);
  }

  Future<ScanPreset?> getLastUsedPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final signature = prefs.getString(_lastUsedPresetGlobalKey);

    if (signature == null || signature.isEmpty) {
      return null;
    }

    final presets = await getPresets();
    for (final preset in presets) {
      if (preset.signature == signature) {
        return preset;
      }
    }

    return null;
  }

  Future<void> savePresetCounts(String signature, int ok, int ng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_countsPrefix + signature, jsonEncode({'ok': ok, 'ng': ng}));
  }

  Future<Map<String, int>> getPresetCounts(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_countsPrefix + signature);
    if (raw == null || raw.isEmpty) {
      return {'ok': 0, 'ng': 0};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'ok': (decoded['ok'] as num?)?.toInt() ?? 0,
        'ng': (decoded['ng'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {'ok': 0, 'ng': 0};
    }
  }

  Future<void> saveZoomLevel(double level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_globalZoomKey, level);
  }

  Future<double> getZoomLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_globalZoomKey) ?? 0.0;
  }

  String _signatureForCodes(List<String> codes) {
    final sorted = [...codes]..sort();
    return sorted.join('|');
  }
}
