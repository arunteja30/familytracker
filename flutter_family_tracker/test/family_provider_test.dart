import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/models/alert_item_model.dart';
import 'package:flutter_family_tracker/models/chat_message_model.dart';
import 'package:flutter_family_tracker/models/family_member_model.dart';
import 'package:flutter_family_tracker/models/geofence_place_model.dart';
import 'package:flutter_family_tracker/models/location_details_model.dart';
import 'package:flutter_family_tracker/providers/family_provider.dart';
import 'package:flutter_family_tracker/services/database_service.dart';
import 'package:flutter_family_tracker/services/location_service.dart';

class FakeDatabaseService extends Fake implements DatabaseService {
  final members = <String, StreamController<List<FamilyMemberModel>>>{};
  final locations = <String, StreamController<LocationDetailsModel?>>{};
  final subscribedFamilies = <String>[];
  int locationSubscriptions = 0;
  int memberFetches = 0;

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) async {
    memberFetches++;
    return [];
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers(String familyName) {
    subscribedFamilies.add(familyName);
    return members.putIfAbsent(
      familyName,
      () => StreamController<List<FamilyMemberModel>>.broadcast(),
    ).stream;
  }

  @override
  Stream<LocationDetailsModel?> streamLocationDetails(String mobile) {
    locationSubscriptions++;
    return locations.putIfAbsent(
      mobile,
      () => StreamController<LocationDetailsModel?>.broadcast(),
    ).stream;
  }

  @override
  Stream<Map<String, dynamic>?> streamEmergencyAlerts(String familyName) =>
      const Stream.empty();

  @override
  Stream<List<ChatMessageModel>> streamChatMessages(String familyName, {int limit = 100}) =>
      const Stream.empty();

  @override
  Stream<List<GeofencePlaceModel>> streamFamilyPlaces(String familyName) =>
      const Stream.empty();

  @override
  Stream<List<AlertItemModel>> streamFamilyAlerts(String familyName) =>
      const Stream.empty();
}

class FakeLocationService extends Fake implements LocationService {
  @override
  void stopContinuousTracking() {}
}

void main() {
  late FakeDatabaseService database;
  late FamilyProvider provider;

  setUp(() {
    database = FakeDatabaseService();
    provider = FamilyProvider(
      databaseService: database,
      locationService: FakeLocationService(),
    );
  });

  tearDown(() async {
    provider.dispose();
    for (final stream in database.members.values) {
      await stream.close();
    }
    for (final stream in database.locations.values) {
      await stream.close();
    }
  });

  testWidgets('idle notifications schedule a frame', (tester) async {
    await tester.pump();
    var notifications = 0;
    provider.addListener(() => notifications++);
    final switching = provider.switchFamilyGroup('Family');
    expect(tester.binding.hasScheduledFrame, isTrue);
    database.members['Family']!.add([]);
    await tester.pump(const Duration(milliseconds: 100));
    await switching;
    expect(database.memberFetches, 0);
    notifications = 0;
    provider.markAllChatRead();
    await tester.pump(const Duration(milliseconds: 100));
    expect(notifications, 1);
  });

  testWidgets('latest switch wins when earlier request completes last', (tester) async {
    final first = provider.switchFamilyGroup('First');
    final second = provider.switchFamilyGroup('Second');
    database.members['Second']!.add([]);
    await tester.pump(const Duration(milliseconds: 100));
    await second;
    database.members['First']!.add([FamilyMemberModel(name: 'Stale', mobile: '1')]);
    await tester.pump(const Duration(milliseconds: 100));
    await first;
    expect(provider.currentFamilyName, 'Second');
    expect(database.subscribedFamilies, ['First', 'Second']);
    expect(provider.isLoading, isFalse);
    expect(database.memberFetches, 0);
  });

  testWidgets('stale completion cannot release newer loading state', (tester) async {
    final first = provider.switchFamilyGroup('First');
    final second = provider.switchFamilyGroup('Second');
    database.members['First']!.add([]);
    await tester.pump(const Duration(milliseconds: 100));
    await first;
    expect(provider.isLoading, isTrue);
    database.members['Second']!.add([]);
    await tester.pump(const Duration(milliseconds: 100));
    await second;
    expect(provider.isLoading, isFalse);
  });

  testWidgets('member snapshots reuse location listeners and accept removals', (tester) async {
    final member = FamilyMemberModel(
      name: 'Member', mobile: '9876543210', relationship: 'Member',
      memberId: 'member', familyName: 'Family',
    );
    final switching = provider.switchFamilyGroup('Family');
    database.members['Family']!.add([member]);
    await tester.pump(const Duration(milliseconds: 100));
    await switching;
    expect(database.locationSubscriptions, 1);
    database.members['Family']!.add([]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(provider.familyMembers, isEmpty);
  });

  testWidgets('location snapshots do not advance dashboard revision', (tester) async {
    final member = FamilyMemberModel(
      name: 'Member', mobile: '9876543210', relationship: 'Member',
      memberId: 'member', familyName: 'Family',
    );
    final switching = provider.switchFamilyGroup('Family');
    database.members['Family']!.add([member]);
    await tester.pump(const Duration(milliseconds: 100));
    await switching;
    final revision = provider.dashboardRevision;
    final location = LocationDetailsModel(
      latitude: 1,
      longitude: 2,
      timeStamp: 100,
      date: '2026-10-12',
      batteryPercentage: 80,
      address: 'Test location',
    );

    database.locations[member.mobile]!.add(location);
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.locationForPhone(member.mobile), same(location));
    expect(provider.dashboardRevision, revision);
  });

  testWidgets('timed out switches release loading and attach live streams', (tester) async {
    final switching = provider.switchFamilyGroup('Offline');
    await switching;
    await tester.pump(const Duration(seconds: 3));
    expect(provider.isLoading, isFalse);
    expect(database.subscribedFamilies, ['Offline']);
    expect(database.memberFetches, 0);
  });
}