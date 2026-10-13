import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/models/family_member_model.dart';
import 'package:flutter_family_tracker/services/database_service.dart';

class FakeEvent extends Fake implements DatabaseEvent {}

class FakeReference extends Fake implements DatabaseReference {
  final Stream<DatabaseEvent> events;
  FakeReference(this.events);

  @override
  DatabaseReference child(String path) => this;

  @override
  Stream<DatabaseEvent> get onValue => events;
}

class FakeFirebaseDatabase extends Fake implements FirebaseDatabase {
  final events = StreamController<DatabaseEvent>.broadcast();

  @override
  DatabaseReference ref([String? path]) => FakeReference(events.stream);
}

class ControlledDatabaseService extends DatabaseService {
  ControlledDatabaseService(FirebaseDatabase database) : super(database: database);

  final requests = <Completer<List<FamilyMemberModel>>>[];

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) {
    final request = Completer<List<FamilyMemberModel>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  test('live location update includes normalized and legacy paths atomically', () {
    final location = {'latitude': 1.0, 'longitude': 2.0};
    final updates = DatabaseService.buildLiveLocationUpdates(
      '+1 (415) 555-0100',
      location,
    );

    expect(updates, hasLength(4));
    expect(updates['locationList/+1 (415) 555-0100'], same(location));
    expect(updates['LocationDetails/+1 (415) 555-0100'], same(location));
    expect(updates['locationList/+14155550100'], same(location));
    expect(updates['LocationDetails/+14155550100'], same(location));
    expect(DatabaseService.buildLiveLocationUpdates('', location), isEmpty);
  });

  test('location history update includes both schema aliases', () {
    final values = {'timeStamp': 123};
    final updates = DatabaseService.buildLocationHistoryUpdates(
      mobile: '+1 (415) 555-0100',
      date: '2026-10-13',
      timeKey: '123',
      values: values,
    );

    expect(updates, hasLength(4));
    expect(updates['locationHistory/+14155550100/2026-10-13/123'], same(values));
    expect(updates['LocationHistory/+14155550100/2026-10-13/123'], same(values));
  });

  test('merges direct and indexed family members by normalized phone', () {
    final merged = DatabaseService.mergeFamilyMemberSources('Alpha', [
      [
        FamilyMemberModel(
          name: 'Circle Admin',
          mobile: '+91 98765 43210',
          relationship: 'Admin',
          familyName: 'Alpha',
        ),
      ],
      [
        FamilyMemberModel(
          name: 'Signed-in User',
          mobile: '9876543210',
          familyName: 'Alpha',
          isRegistered: true,
        ),
        FamilyMemberModel(
          name: 'Second Member',
          mobile: '9123456789',
          familyName: 'Alpha',
        ),
      ],
    ]);

    expect(merged, hasLength(2));
    expect(merged.map((member) => member.name), contains('Signed-in User'));
    expect(merged.first.relationship, 'Admin');
  });

  test('family names with phone suffixes do not expand to phone aliases', () {
    expect(
      DatabaseService.familyNameCandidates('Smith_9876543210'),
      {'Smith_9876543210'},
    );
    expect(
      DatabaseService.familyNameCandidates('+91 98765 43210'),
      containsAll(['+91 98765 43210', '9876543210', '+9876543210']),
    );

    final merged = DatabaseService.mergeFamilyMemberSources('Smith_9876543210', [
      [
        FamilyMemberModel(
          name: 'Other Group Member',
          mobile: '9876543210',
          familyName: 'Jones_9876543210',
        ),
      ],
    ]);
    expect(merged, isEmpty);
  });

  test('member events are coalesced and reads never overlap', () async {
    final database = FakeFirebaseDatabase();
    final service = ControlledDatabaseService(database);
    final snapshots = <List<FamilyMemberModel>>[];
    final subscription = service.streamFamilyMembers('Family').listen(snapshots.add);

    database.events.add(FakeEvent());
    database.events.add(FakeEvent());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(service.requests, hasLength(1));

    database.events.add(FakeEvent());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(service.requests, hasLength(1));

    service.requests.first.complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(snapshots, [<FamilyMemberModel>[]]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(service.requests, hasLength(2));

    await subscription.cancel();
    service.requests.last.complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(snapshots, hasLength(1));
    await database.events.close();
  });

  test('cancelling a member stream cancels scheduled reads', () async {
    final database = FakeFirebaseDatabase();
    final service = ControlledDatabaseService(database);
    final subscription = service.streamFamilyMembers('Family').listen((_) {});
    database.events.add(FakeEvent());
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(service.requests, isEmpty);
    await database.events.close();
  });
}