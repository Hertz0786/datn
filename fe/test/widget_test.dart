import 'package:flutter_test/flutter_test.dart';

import 'package:fe/main.dart';

void main() {
  testWidgets('Onboarding flow renders and advances', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('A bright place to share'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Kind and friendly chat'), findsOneWidget);
  });
}
