import 'package:firebase_database/firebase_database.dart';
import '../constants/app_constants.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../models/registration_model.dart';

class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Helper: Normalize & Match Phone Numbers (e.g. +919876543210 vs 9876543210)
  static bool matchPhones(String p1, String p2) {
    if (p1.isEmpty || p2.isEmpty) return false;
    if (p1.trim() == p2.trim()) return true;
    final d1 = p1.replaceAll(RegExp(r'\D'), '');
    final d2 = p2.replaceAll(RegExp(r'\D'), '');
    if (d1.isEmpty || d2.isEmpty) return false;
    if (d1 == d2) return true;
    final s1 = d1.length >= 10 ? d1.substring(d1.length - 10) : d1;
    final s2 = d2.length >= 10 ? d2.substring(d2.length - 10) : d2;
    return s1 == s2;
  }

  // Stream of Family Members for a given Group Name
  Stream<List<FamilyMemberModel>> streamFamilyMembers(String familyName) {
    return _db.ref(AppConstants.familyMemberList).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return [];

      final List<FamilyMemberModel> members = [];
      final targetFamily = familyName.trim().toLowerCase();

      void processItem(dynamic val, [String? key]) {
        if (val is Map) {
          final model = FamilyMemberModel.fromJson(val);
          if (model.memberId.isEmpty && key != null) {
            model.memberId = key;
          }
          if (targetFamily.isEmpty ||
              model.familyName.trim().toLowerCase() == targetFamily) {
            members.add(model);
          }
        }
      }

      if (data is Map) {
        data.forEach((k, v) => processItem(v, k.toString()));
      } else if (data is List) {
        for (int i = 0; i < data.length; i++) {
          if (data[i] != null) processItem(data[i], i.toString());
        }
      }

      return members;
    });
  }

  // Get Family Members Once
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) async {
    try {
      final snapshot = await _db.ref(AppConstants.familyMemberList).get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value;
      final List<FamilyMemberModel> members = [];
      final targetFamily = familyName.trim().toLowerCase();

      void processItem(dynamic val, [String? key]) {
        if (val is Map) {
          final model = FamilyMemberModel.fromJson(val);
          if (model.memberId.isEmpty && key != null) {
            model.memberId = key;
          }
          if (targetFamily.isEmpty ||
              model.familyName.trim().toLowerCase() == targetFamily) {
            members.add(model);
          }
        }
      }

      if (data is Map) {
        data.forEach((k, v) => processItem(v, k.toString()));
      } else if (data is List) {
        for (int i = 0; i < data.length; i++) {
          if (data[i] != null) processItem(data[i], i.toString());
        }
      }

      return members;
    } catch (e) {
      return [];
    }
  }

  // Find all Family Groups associated with a Phone Number
  Future<List<String>> getFamilyNamesForPhone(String mobile) async {
    try {
      final snapshot = await _db.ref(AppConstants.familyMemberList).get();
      final Set<String> groups = {};

      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value;
        void checkItem(dynamic val) {
          if (val is Map) {
            final model = FamilyMemberModel.fromJson(val);
            if (matchPhones(model.mobile, mobile) &&
                model.familyName.trim().isNotEmpty) {
              groups.add(model.familyName.trim());
            }
          }
        }

        if (data is Map) {
          data.forEach((k, v) => checkItem(v));
        } else if (data is List) {
          for (var item in data) {
            if (item != null) checkItem(item);
          }
        }
      }

      // Check UserFamilyName node fallback
      if (groups.isEmpty) {
        final userFamilySnap =
            await _db.ref(AppConstants.userFamilyName).child(mobile).get();
        if (userFamilySnap.exists && userFamilySnap.value != null) {
          groups.add(userFamilySnap.value.toString().trim());
        }
      }

      return groups.toList();
    } catch (e) {
      return [];
    }
  }

  // Stream of Real-time Location for a Specific Mobile Number
  Stream<LocationDetailsModel?> streamLocationDetails(String mobile) {
    return _db.ref(AppConstants.locationList).child(mobile).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return null;
      return LocationDetailsModel.fromJson(data);
    });
  }

  // Get Location Details Once
  Future<LocationDetailsModel?> getLocationDetails(String mobile) async {
    try {
      var snapshot =
          await _db.ref(AppConstants.locationList).child(mobile).get();
      if (!snapshot.exists || snapshot.value == null) {
        snapshot = await _db
            .ref(AppConstants.legacyLocationList)
            .child(mobile)
            .get();
      }
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return null;
      }
      return LocationDetailsModel.fromJson(snapshot.value as Map);
    } catch (e) {
      return null;
    }
  }

  // Save/Update Live Location
  Future<void> saveLocation(
      String mobile, LocationDetailsModel location) async {
    try {
      final json = location.toJson();
      await _db.ref(AppConstants.locationList).child(mobile).set(json);
      await _db.ref(AppConstants.legacyLocationList).child(mobile).set(json);

      // Save to Location History
      if (location.date.isNotEmpty) {
        final timeKey = location.timeStamp > 0
            ? location.timeStamp.toString()
            : DateTime.now().millisecondsSinceEpoch.toString();
        await _db
            .ref(AppConstants.locationHistory)
            .child(mobile)
            .child(location.date)
            .child(timeKey)
            .set(json);
      }
    } catch (_) {}
  }

  // Get Location History for a Date
  Future<List<LocationDetailsModel>> getLocationHistory(
      String mobile, String date) async {
    try {
      final snapshot = await _db
          .ref(AppConstants.locationHistory)
          .child(mobile)
          .child(date)
          .get();

      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value;
      final List<LocationDetailsModel> history = [];
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            history.add(LocationDetailsModel.fromJson(value));
          }
        });
      }
      history.sort((a, b) => a.timeStamp.compareTo(b.timeStamp));
      return history;
    } catch (e) {
      return [];
    }
  }

  // Register Phone Profile
  Future<void> registerPhone(RegistrationModel model) async {
    try {
      await _db
          .ref(AppConstants.registrationDetails)
          .child(model.phone)
          .set(model.toJson());
      await _db.ref(AppConstants.userList).child(model.phone).set(model.toJson());
    } catch (e) {
      rethrow;
    }
  }

  // Add or Update Family Member
  Future<void> addFamilyMember(FamilyMemberModel member) async {
    try {
      final memberId = member.memberId.isNotEmpty
          ? member.memberId
          : DateTime.now().millisecondsSinceEpoch.toString();
      member.memberId = memberId;

      await _db
          .ref(AppConstants.familyMemberList)
          .child(memberId)
          .set(member.toJson());

      if (member.familyName.isNotEmpty) {
        await _db
            .ref(AppConstants.familyList)
            .child(member.familyName)
            .set(member.familyName);
      }
    } catch (e) {
      rethrow;
    }
  }

  // Delete Family Member
  Future<void> deleteFamilyMember(String memberId, String mobile) async {
    try {
      if (memberId.isNotEmpty) {
        await _db.ref(AppConstants.familyMemberList).child(memberId).remove();
      }
      if (mobile.isNotEmpty) {
        await _db.ref(AppConstants.locationList).child(mobile).remove();
      }
    } catch (e) {
      rethrow;
    }
  }
}
