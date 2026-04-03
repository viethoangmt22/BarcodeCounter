class ScanConfig {
  const ScanConfig({
    required this.masterCode,
    required this.bagTarget,
    required this.boxTarget,
  });

  final String masterCode;
  final int bagTarget;
  final int boxTarget;
}
