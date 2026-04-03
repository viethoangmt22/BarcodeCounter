import 'package:flutter_test/flutter_test.dart';

import 'package:barcodecount/main.dart';

void main() {
  testWidgets('setup screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BarcodeCountApp());

    expect(find.text('Barcode Setup'), findsOneWidget);
  });
}
