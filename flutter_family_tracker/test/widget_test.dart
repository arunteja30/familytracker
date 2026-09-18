import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/constants/app_theme.dart';
import 'package:flutter_family_tracker/constants/app_colors.dart';

void main() {
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
