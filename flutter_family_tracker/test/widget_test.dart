import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/constants/app_theme.dart';
import 'package:flutter_family_tracker/constants/app_colors.dart';
import 'package:flutter_family_tracker/utils/marker_generator.dart';

void main() {
  testWidgets('map markers can be generated, cached, and regenerated',
      (tester) async {
    await tester.runAsync(() async {
      MarkerGenerator.clearCache();
      final member = await MarkerGenerator.createCustomMemberMarker(name: 'Alex');
      final cached = await MarkerGenerator.createCustomMemberMarker(name: 'Alex');
      expect(identical(member, cached), isTrue);
      final pin = await MarkerGenerator.createPushpinMarker(pinColor: Colors.green);
      final cachedPin = await MarkerGenerator.createPushpinMarker(pinColor: Colors.green);
      expect(identical(pin, cachedPin), isTrue);
      MarkerGenerator.clearCache();
      final regenerated = await MarkerGenerator.createCustomMemberMarker(name: 'Alex');
      expect(identical(member, regenerated), isFalse);
      MarkerGenerator.clearCache();
    });
  });

  testWidgets('AppTheme and Branding Widget Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          appBar: AppBar(title: const Text('FamilyTracker')),
          body: const Center(
            child: Text('Live Safety Tracking', style: TextStyle(color: AppColors.primary)),
          ),
        ),
      ),
    );

    expect(find.text('FamilyTracker'), findsOneWidget);
    expect(find.text('Live Safety Tracking'), findsOneWidget);
  });
}
