class ScanAlertLevel {
  const ScanAlertLevel({required this.quantity, required this.message});

  final int quantity;
  final String message;

  Map<String, dynamic> toJson() {
    return {'quantity': quantity, 'message': message};
  }

  factory ScanAlertLevel.fromJson(Map<String, dynamic> json) {
    return ScanAlertLevel(
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      message: (json['message'] as String?) ?? '',
    );
  }
}

class ScanConfig {
  const ScanConfig({
    required this.requiredCodes,
    required this.okMessage,
    required this.ngMessage,
    required this.alertLevels,
    this.colorValue,
    this.productName,
  });

  final List<String> requiredCodes;
  final String okMessage;
  final String ngMessage;
  final List<ScanAlertLevel> alertLevels;
  final int? colorValue;
  final String? productName;

  String get masterCode => requiredCodes.isNotEmpty ? requiredCodes.first : '';

  bool get requiresTwoCodes => requiredCodes.length >= 2;

  bool matchesDetectedCodes(Iterable<String> detectedCodes) {
    final detectedSet = detectedCodes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    if (requiredCodes.isEmpty) {
      return false;
    }

    return requiredCodes.every(detectedSet.contains);
  }

  int get bagTarget => alertLevels.isNotEmpty ? alertLevels.first.quantity : 10;

  int get boxTarget => alertLevels.length > 1 ? alertLevels[1].quantity : 100;

  factory ScanConfig.defaults() {
    return const ScanConfig(
      requiredCodes: [],
      okMessage: 'OK con dê',
      ngMessage: 'NG NG NG. Sai tem giấy rồi Bà Chị ơi',
      alertLevels: [
        ScanAlertLevel(
          quantity: 10,
          message: 'Đủ 10 cái rồi đóng túi nilon đi',
        ),
        ScanAlertLevel(quantity: 100, message: 'Đủ 100 cái rồi đóng thùng đi'),
      ],
      colorValue: null,
      productName: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requiredCodes': requiredCodes,
      'okMessage': okMessage,
      'ngMessage': ngMessage,
      'alertLevels': alertLevels.map((level) => level.toJson()).toList(),
      'colorValue': colorValue,
      'productName': productName,
    };
  }

  factory ScanConfig.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['requiredCodes'];
    final codes = rawCodes is List
        ? rawCodes.map((e) => e.toString().trim()).where((e) => e.isNotEmpty)
        : const <String>[];

    final rawLevels = json['alertLevels'];
    final levels = rawLevels is List
        ? rawLevels
              .whereType<Map>()
              .map(
                (item) =>
                    item.map((key, value) => MapEntry(key.toString(), value)),
              )
              .map(ScanAlertLevel.fromJson)
              .toList()
        : const <ScanAlertLevel>[];

    return ScanConfig(
      requiredCodes: codes.toList(),
      okMessage: (json['okMessage'] as String?) ?? '',
      ngMessage: (json['ngMessage'] as String?) ?? '',
      alertLevels: levels.isEmpty ? ScanConfig.defaults().alertLevels : levels,
      colorValue: json['colorValue'] as int?,
      productName: json['productName'] as String?,
    );
  }
}

class ScanPreset {
  const ScanPreset({required this.requiredCodes, required this.config});

  final List<String> requiredCodes;
  final ScanConfig config;

  String get name {
    if (config.productName != null && config.productName!.isNotEmpty) {
      return config.productName!;
    }

    if (requiredCodes.length == 2) {
      final first = requiredCodes[0];
      final second = requiredCodes[1];
      return '$first + $second / $second + $first';
    }

    return requiredCodes.join(' + ');
  }

  String get signature {
    final sorted = requiredCodes.map((e) => e.trim()).toList()..sort();
    return sorted.join('|');
  }

  Map<String, dynamic> toJson() {
    return {'requiredCodes': requiredCodes, 'config': config.toJson()};
  }

  factory ScanPreset.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['requiredCodes'];
    if (rawCodes is List) {
      final parsedCodes = rawCodes
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();

      return ScanPreset(
        requiredCodes: parsedCodes,
        config: json['config'] is Map
            ? ScanConfig.fromJson(
                (json['config'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              )
            : ScanConfig.defaults(),
      );
    }

    final legacySample = (json['sampleCode'] as String?) ?? '';
    final legacyCodes = legacySample.contains('|')
        ? legacySample
              .split('|')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : legacySample.trim().isEmpty
        ? const <String>[]
        : <String>[legacySample.trim()];

    return ScanPreset(
      requiredCodes: legacyCodes,
      config: json['config'] is Map
          ? ScanConfig.fromJson(
              (json['config'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : ScanConfig.defaults(),
    );
  }
}
