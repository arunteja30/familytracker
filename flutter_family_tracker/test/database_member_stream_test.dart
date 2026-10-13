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