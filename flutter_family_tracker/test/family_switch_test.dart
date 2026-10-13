import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_family_tracker/models/alert_item_model.dart';
import 'package:flutter_family_tracker/models/chat_message_model.dart';
import 'package:flutter_family_tracker/models/family_member_model.dart';
import 'package:flutter_family_tracker/models/family_group_summary.dart';
import 'package:flutter_family_tracker/models/geofence_place_model.dart';
import 'package:flutter_family_tracker/models/location_details_model.dart';
import 'package:flutter_family_tracker/providers/family_provider.dart';
import 'package:flutter_family_tracker/services/database_service.dart';
import 'package:flutter_family_tracker/services/location_service.dart';
import 'package:flutter_family_tracker/ui/widgets/group_switcher_dialog.dart';

class _Database extends Fake implements DatabaseService {
  final members = <String, StreamController<List<FamilyMemberModel>>>{};
  int memberFetches = 0;

  @override
  Future<List<FamilyGroupSummary>> getUserFamilySummaries(String userPhone) async => [];

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) async {
    memberFetches++;
    return [];
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers(String familyName) =>
      members.putIfAbsent(familyName, StreamController.broadcast).stream;

  @override
  Stream<Map<String, dynamic>?> streamEmergencyAlerts(String familyName) =>
      const Stream.empty();

  @override
    Stream<List<ChatMessageModel>> streamChatMessages(String familyName,
      {int limit = 100}) =>
      const Stream.empty();

  @override
  Stream<List<GeofencePlaceModel>> streamFamilyPlaces(String familyName) =>
      const Stream.empty();

  @override
  Stream<List<AlertItemModel>> streamFamilyAlerts(String familyName) =>
      const Stream.empty();

  @override
  Stream<LocationDetailsModel?> streamLocationDetails(String mobile) =>
      const Stream.empty();

  Future<void> close() async {
    for (final controller in members.values) {
      await controller.close();
    }
  }
}

class _Location extends Fake implements LocationService {
  @override
  void stopContinuousTracking() {}
}

FamilyMemberModel _member(String name) =>
    FamilyMemberModel(name: name, mobile: '9876543210');

void main() {
  late _Database database;
  late FamilyProvider provider;

  setUp(() {
    database = _Database();
    provider = FamilyProvider(
      databaseService: database,
      locationService: _Location(),
    );
  });

  tearDown(() async {
    provider.dispose();
    await database.close();
  });

  testWidgets('live members load without waiting for the initial read',
      (tester) async {
    final switching = provider.switchFamilyGroup('Alpha');
    expect(database.members['Alpha']!.hasListener, isTrue);
    database.members['Alpha']!.add([_member('Live')]);
    await tester.pump(const Duration(milliseconds: 100));
    await switching;

    expect(provider.isLoading, isFalse);
    expect(provider.familyMembers.single.name, 'Live');
    expect(database.memberFetches, 0);
  });

  testWidgets('rapid switches ignore the old group snapshot', (tester) async {
    final first = provider.switchFamilyGroup('Alpha');
    final second = provider.switchFamilyGroup('Beta');
    expect(database.members['Alpha']!.hasListener, isFalse);
    database.members['Beta']!.add([_member('Beta member')]);
    await tester.pump(const Duration(milliseconds: 100));
    await second;
    database.members['Alpha']!.add([_member('Alpha member')]);
    await tester.pump(const Duration(milliseconds: 100));
    await first;
    expect(provider.currentFamilyName, 'Beta');
    expect(provider.familyMembers.single.name, 'Beta member');
    expect(provider.isLoading, isFalse);
  });

  testWidgets('offline switch recovers through later live updates',
      (tester) async {
    final switching = provider.switchFamilyGroup('Alpha');
    await switching;
    await tester.pump(const Duration(seconds: 3));
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(database.members['Alpha']!.hasListener, isTrue);

    database.members['Alpha']!.add([_member('Recovered')]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(provider.familyMembers.single.name, 'Recovered');
    expect(provider.errorMessage, isNull);
  });

  testWidgets('offline switch has a bounded loading state', (tester) async {
    final switching = provider.switchFamilyGroup('Alpha');
    await switching;
    await tester.pump(const Duration(seconds: 3));
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(database.members['Alpha']!.hasListener, isTrue);
  });

  for (final target in ['Alpha', 'Beta']) {
    testWidgets('repeated dialog taps are handled once for $target',
        (tester) async {
      final switched = <String>[];
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => GroupSwitcherDialog(
                    currentGroup: 'Alpha',
                    availableGroups: const ['Alpha', 'Beta'],
                    onSwitch: switched.add,
                  ),
                ),
                child: const Text('Open circles'),
              );
            }),
          ),
        ),
      ));
      await tester.tap(find.text('Open circles'));
      await tester.pumpAndSettle();
      final tap = tester.widget<InkWell>(find.ancestor(
        of: find.text(target).first,
        matching: find.byType(InkWell),
      ).first).onTap!;
      tap();
      tap();
      await tester.pumpAndSettle();
      expect(switched, target == 'Alpha' ? isEmpty : ['Beta']);
      expect(find.byType(GroupSwitcherDialog), findsNothing);
      expect(find.text('Open circles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}