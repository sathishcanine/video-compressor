import 'package:flutter_test/flutter_test.dart';

import 'package:vidcompressor/main.dart';

void main() {
  testWidgets('Shows VidPress header', (WidgetTester tester) async {
    await tester.pumpWidget(const VidPressApp());
    await tester.pumpAndSettle();
    expect(find.text('VidPress'), findsOneWidget);
    expect(find.text('Pick a Video'), findsOneWidget);
  });
}
