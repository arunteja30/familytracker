import 'package:firebase_database/firebase_database.dart';
import '../constants/app_constants.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../models/registration_model.dart';

class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Stream of Family Members in a Group
  Stream<List<FamilyMemberModel>> streamFamilyMembers(String familyName) {
    return _db.ref(AppConstants.familyDbName).child(familyName).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return [];

      final List<FamilyMemberModel> members = [];
      if (data is List) {
        for (var item in data) {
          if (item != null && item is Map) {
            members.add(FamilyMemberModel.fromJson(item));
          }
        }
      } else if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            members.add(FamilyMemberModel.fromJson(value));
          }
        });
      }
      return members;
    });
  }

  // Get Family Members Once
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) async {
    try {
      final snapshot = await _db.ref(AppConstants.familyDbName).child(familyName).get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value;
      final List<FamilyMemberModel> members = [];
      if (data is List) {
        for (var item in data) {
          if (item != null && item is Map) {
            members.add(FamilyMemberModel.fromJson(item));
          }
        }
      } else if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            members.add(FamilyMemberModel.fromJson(value));
          }
        });
      }
      return members;
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
      final snapshot = await _db.ref(AppConstants.locationList).child(mobile).get();
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return null;
      }
      return LocationDetailsModel.fromJson(snapshot.value as Map);
    } catch (e) {
      return null;
    }
  }

  // Save/Update Live Location
  Future<void> saveLocation(String mobile, LocationDetailsModel location) async {
    try {
      await _db.ref(AppConstants.locationList).child(mobile).set(location.toJson());
      
      // Also log to Location History
      if (location.date.isNotEmpty) {
        final timeKey = location.timeStamp > 0
            ? location.timeStamp.toString()
            : DateTime.now().millisecondsSinceEpoch.toString();
        await _db
            .ref(AppConstants.locationHistory)
            .child(mobile)
            .child(location.date)
            .child(timeKey)
            .set(location.toJson());
      }
    } catch (e) {
      // Ignore background network transient errors
    }
  }

  // Get Location History for a Date Range
  Future<List<LocationDetailsModel>> getLocationHistory(String mobile, String date) async {
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

  // Get Family Name Associated with a Mobile Number
  Future<String?> getFamilyNameFromMobile(String mobile) async {
    try {
      final snapshot = await _db.ref(AppConstants.userFamilyName).child(mobile).get();
      if (snapshot.exists && snapshot.value != null) {
        return snapshot.value.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Register Phone Profile
  Future<void> registerPhone(RegistrationModel model) async {
    try {
      await _db
          .ref(AppConstants.registrationDetails)
          .child(model.phone)
          .set(model.toJson());
    } catch (e) {
      rethrow;
    }
  }

  // Save User Family Name Mapping
  Future<void> saveUserFamilyNameMapping(String mobile, String familyName) async {
    try {
      await _db.ref(AppConstants.userFamilyName).child(mobile).set(familyName);
    } catch (e) {
      rethrow;
    }
  }

  // Add Family Member
  Future<void> addFamilyMember(String familyName, FamilyMemberModel member) async {
    try {
      final members = await getFamilyMembers(familyName);
      
      // Update existing or add new
      final index = members.indexWhere((m) => m.mobile == member.mobile);
      if (index >= 0) {
        members[index] = member;
      } else {
        members.add(member);
      }

      await _db.ref(AppConstants.familyDbName).child(familyName).set(
        members.map((m) => m.toJson()).toList(),
      );

      // Save user-to-family mapping
      await saveUserFamilyNameMapping(member.mobile, familyName);
    } catch (e) {
      rethrow;
    }
  }

  // Delete Family Member
  Future<void> deleteFamilyMember(String familyName, String mobile) async {
    try {
      final members = await getFamilyMembers(familyName);
      members.removeWhere((m) => m.mobile == mobile);
      await _db.ref(AppConstants.familyDbName).child(familyName).set(
        members.map((m) => m.toJson()).toList(),
      );
    } catch (e) {
      rethrow;
    }
  }
}
