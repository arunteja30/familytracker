import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_family_tracker/services/preferences_service.dart';
import 'package:flutter_family_tracker/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  testWidgets('App basic test', (WidgetTester tester) async {
    await tester.pumpWidget(const FamilyTrackerApp());
    expect(find.byType(FamilyTrackerApp), findsOneWidget);
  });
}
