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
    required this.masterCode,
    required this.okMessage,
    required this.ngMessage,
    required this.alertLevels,
  });

  final String masterCode;
  final String okMessage;
  final String ngMessage;
  final List<ScanAlertLevel> alertLevels;

  int get bagTarget => alertLevels.isNotEmpty ? alertLevels.first.quantity : 10;

  int get boxTarget => alertLevels.length > 1 ? alertLevels[1].quantity : 100;

  factory ScanConfig.defaults() {
    return const ScanConfig(
      masterCode: '',
      okMessage: 'OK con dê',
      ngMessage: 'NG NG NG. Sai tem giấy rồi Bà Chị ơi',
      alertLevels: [
        ScanAlertLevel(
          quantity: 10,
          message: 'Đủ 10 cái rồi đóng túi nilon đi',
        ),
        ScanAlertLevel(quantity: 100, message: 'Đủ 100 cái rồi đóng thùng đi'),
      ],
    );
  }
}
