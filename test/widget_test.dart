import 'package:flutter_test/flutter_test.dart';

import 'package:barcodecount/main.dart';

void main() {
  testWidgets('home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BarcodeCountApp());

    expect(find.text('Barcode Counter'), findsOneWidget);
  });
}
