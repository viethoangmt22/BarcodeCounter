import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:barcodecount/services/scanner_utils.dart';

void main() {
  test('pickDetectedObservations prefers barcodes inside center ROI', () {
    final capture = BarcodeCapture(
      size: const Size(1000, 1000),
      barcodes: [
        const Barcode(
          rawValue: 'OUT',
          corners: [
            Offset(10, 10),
            Offset(110, 10),
            Offset(110, 110),
            Offset(10, 110),
          ],
        ),
        const Barcode(
          rawValue: 'IN',
          corners: [
            Offset(450, 450),
            Offset(550, 450),
            Offset(550, 550),
            Offset(450, 550),
          ],
        ),
      ],
    );

    final observations = ScannerUtils.pickDetectedObservations(capture);

    expect(observations.map((e) => e.value), ['IN']);
    expect(observations.single.center, const Offset(500, 500));
  });

  test('pickDetectedObservations falls back when geometry is unavailable', () {
    final capture = BarcodeCapture(
      size: const Size(1000, 1000),
      barcodes: [
        const Barcode(rawValue: 'B'),
        const Barcode(rawValue: 'A'),
        const Barcode(rawValue: 'A'),
      ],
    );

    final observations = ScannerUtils.pickDetectedObservations(capture);

    expect(observations.map((e) => e.value), ['A', 'B']);
    expect(observations.every((e) => !e.hasGeometry), isTrue);
  });
}
