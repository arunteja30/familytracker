import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/main.dart';

void main() {
  testWidgets('App basic test', (WidgetTester tester) async {
    await tester.pumpWidget(const FamilyTrackerApp());
    expect(find.byType(FamilyTrackerApp), findsOneWidget);
  });
}
