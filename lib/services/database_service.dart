import 'package:flutter/foundation.dart';
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

  // Parse generic snapshot into list of FamilyMemberModel
  static List<FamilyMemberModel> parseMembersFromSnapshot(
      dynamic data, [String? fallbackFamilyName]) {
    final List<FamilyMemberModel> result = [];
    if (data == null) return result;

    void processItem(dynamic val, [String? key]) {
      if (val is Map) {
        final model = FamilyMemberModel.fromJson(val);
        if (model.memberId.isEmpty && key != null) {
          model.memberId = key;
        }
        if (model.familyName.isEmpty && fallbackFamilyName != null) {
          model.familyName = fallbackFamilyName;
        }
        result.add(model);
      }
    }

    if (data is Map) {
      data.forEach((k, v) {
        if (v is Map && (v.containsKey('name') || v.containsKey('mobile') || v.containsKey('mobileNo'))) {
          processItem(v, k.toString());
        } else if (v is Map) {
          // Nested group like { "MyFamily": { "member1": {...} } }
          v.forEach((nestedK, nestedV) {
            processItem(nestedV, nestedK.toString());
          });
        }
      });
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        if (data[i] != null) processItem(data[i], i.toString());
      }
    }

    return result;
  }

  // Stream of Family Members for a given Group Name (listening to multiple nodes)
  Stream<List<FamilyMemberModel>> streamFamilyMembers(String familyName) {
    return _db.ref(AppConstants.familyMemberList).onValue.map((event) {
      final members = parseMembersFromSnapshot(event.snapshot.value, familyName);
      final target = familyName.trim().toLowerCase();

      final filtered = members.where((m) {
        if (target.isEmpty) return true;
        return m.familyName.trim().toLowerCase() == target;
      }).toList();

      debugPrint('[FamilyTracker] Streamed ${filtered.length} members for $familyName');
      return filtered;
    });
  }

  // Get All Members Across All Known DB Nodes
  Future<List<FamilyMemberModel>> getAllDatabaseMembers() async {
    final List<FamilyMemberModel> all = [];
    final seen = <String>{};

    void addUnique(List<FamilyMemberModel> list) {
      for (var m in list) {
        final key = '${m.mobile}_${m.familyName}';
        if (!seen.contains(key) && m.mobile.isNotEmpty) {
          seen.add(key);
          all.add(m);
        }
      }
    }

    try {
      // 1. Check familyMembersList
      final snap1 = await _db.ref(AppConstants.familyMemberList).get();
      if (snap1.exists && snap1.value != null) {
        addUnique(parseMembersFromSnapshot(snap1.value));
      }

      // 2. Check familyNames
      final snap2 = await _db.ref(AppConstants.familyDbName).get();
      if (snap2.exists && snap2.value != null) {
        addUnique(parseMembersFromSnapshot(snap2.value));
      }

      // 3. Check legacy FamilyDetails
      final snap3 = await _db.ref(AppConstants.legacyFamilyDb).get();
      if (snap3.exists && snap3.value != null) {
        addUnique(parseMembersFromSnapshot(snap3.value));
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Error fetching all members: $e');
    }

    return all;
  }

  // Get Family Members for a Specific Group
  Future<List<FamilyMemberModel>> getFamilyMembers(String familyName) async {
    final allMembers = await getAllDatabaseMembers();
    final target = familyName.trim().toLowerCase();

    if (target.isEmpty) return allMembers;

    final filtered = allMembers.where((m) {
      return m.familyName.trim().toLowerCase() == target;
    }).toList();

    debugPrint('[FamilyTracker] Found ${filtered.length} members for family $familyName');
    return filtered;
  }

  // Find all Family Groups associated with a Phone Number
  Future<List<String>> getFamilyNamesForPhone(String mobile) async {
    final allMembers = await getAllDatabaseMembers();
    final Set<String> groups = {};

    debugPrint('[FamilyTracker] Searching groups for phone: $mobile among ${allMembers.length} members');

    for (var member in allMembers) {
      if (matchPhones(member.mobile, mobile) && member.familyName.trim().isNotEmpty) {
        groups.add(member.familyName.trim());
      }
    }

    // Check UserFamilyName node fallback
    if (groups.isEmpty) {
      try {
        final snap = await _db.ref(AppConstants.userFamilyName).child(mobile).get();
        if (snap.exists && snap.value != null) {
          groups.add(snap.value.toString().trim());
        }
      } catch (_) {}
    }

    // Check all group names in familyList / familyNames
    if (groups.isEmpty) {
      try {
        final snap = await _db.ref(AppConstants.familyList).get();
        if (snap.exists && snap.value is Map) {
          (snap.value as Map).forEach((k, v) {
            if (k != null && k.toString().trim().isNotEmpty) {
              groups.add(k.toString().trim());
            }
          });
        }
      } catch (_) {}
    }

    debugPrint('[FamilyTracker] Groups found for $mobile: $groups');
    return groups.toList();
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
  // Save Location to Realtime DB & History
  Future<void> saveLocation(
      String mobile, LocationDetailsModel location) async {
    try {
      final json = location.toJson();
      final clean = mobile.replaceAll(RegExp(r'[^0-9+]'), '');

      await _db.ref('locationList').child(mobile).set(json);
      await _db.ref('LocationDetails').child(mobile).set(json);
      if (clean != mobile) {
        await _db.ref('locationList').child(clean).set(json);
        await _db.ref('LocationDetails').child(clean).set(json);
      }

      // Save to Location History under both case conventions
      if (location.date.isNotEmpty) {
        final timeKey = location.timeStamp > 0
            ? location.timeStamp.toString()
            : DateTime.now().millisecondsSinceEpoch.toString();

        await _db
            .ref('locationHistory')
            .child(mobile)
            .child(location.date)
            .child(timeKey)
            .set(json);

        await _db
            .ref('LocationHistory')
            .child(mobile)
            .child(location.date)
            .child(timeKey)
            .set(json);

        if (clean != mobile) {
          await _db
              .ref('locationHistory')
              .child(clean)
              .child(location.date)
              .child(timeKey)
              .set(json);
          await _db
              .ref('LocationHistory')
              .child(clean)
              .child(location.date)
              .child(timeKey)
              .set(json);
        }
      }
    } catch (_) {}
  }

  // Get Location History for a Date with deep multi-path and multi-format matching
  Future<List<LocationDetailsModel>> getLocationHistory(
      String mobile, String date) async {
    final List<LocationDetailsModel> history = [];
    final clean = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;

    final phoneCandidates = {mobile, clean, if (last10.isNotEmpty) last10, '+$clean'};
    final tableCandidates = ['locationHistory', 'LocationHistory', 'location_history'];

    void parseAndAdd(dynamic data) {
      if (data == null) return;
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map) {
            // Check if v itself is a location or if it contains timestamped locations
            if (v.containsKey('latitude') || v.containsKey('lat')) {
              try {
                history.add(LocationDetailsModel.fromJson(v));
              } catch (_) {}
            } else {
              parseAndAdd(v);
            }
          } else if (v is List) {
            parseAndAdd(v);
          }
        });
      } else if (data is List) {
        for (var item in data) {
          if (item is Map) {
            try {
              history.add(LocationDetailsModel.fromJson(item));
            } catch (_) {}
          }
        }
      }
    }

    try {
      // 1. Direct query on date paths
      for (var table in tableCandidates) {
        for (var phone in phoneCandidates) {
          if (phone.isEmpty) continue;
          try {
            final snapshot = await _db
                .ref(table)
                .child(phone)
                .child(date)
                .get();

            if (snapshot.exists && snapshot.value != null) {
              parseAndAdd(snapshot.value);
            }
          } catch (_) {}
        }
      }

      // 2. If empty, query entire user history node and match date prefixes
      if (history.isEmpty) {
        for (var table in tableCandidates) {
          for (var phone in phoneCandidates) {
            if (phone.isEmpty) continue;
            try {
              final snapshot = await _db.ref(table).child(phone).get();
              if (snapshot.exists && snapshot.value is Map) {
                final userMap = snapshot.value as Map;
                userMap.forEach((dateKey, dateVal) {
                  final dk = dateKey.toString();
                  // Check if date key matches YYYY-MM-DD or DD-MM-YYYY or contains the date
                  if (dk == date ||
                      dk.contains(date) ||
                      date.contains(dk) ||
                      _normalizeDate(dk) == _normalizeDate(date)) {
                    parseAndAdd(dateVal);
                  }
                });
              }
            } catch (_) {}
            if (history.isNotEmpty) break;
          }
          if (history.isNotEmpty) break;
        }
      }

      // Deduplicate points by timestamp / coordinates
      final Map<String, LocationDetailsModel> uniquePoints = {};
      for (var p in history) {
        if (p.latitude != 0.0 && p.longitude != 0.0) {
          final key = '${p.timeStamp}_${p.latitude.toStringAsFixed(5)}_${p.longitude.toStringAsFixed(5)}';
          uniquePoints[key] = p;
        }
      }

      final sorted = uniquePoints.values.toList()
        ..sort((a, b) => a.timeStamp.compareTo(b.timeStamp));
      return sorted;
    } catch (e) {
      debugPrint('[FamilyTracker] History fetch error: $e');
      return [];
    }
  }

  String _normalizeDate(String d) {
    return d.replaceAll(RegExp(r'[^0-9]'), '');
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

      final json = member.toJson();

      // Save to familyMembersList/{memberId}
      await _db.ref(AppConstants.familyMemberList).child(memberId).set(json);

      // Save to familyNames/{familyName}/{memberId}
      if (member.familyName.isNotEmpty) {
        await _db
            .ref(AppConstants.familyDbName)
            .child(member.familyName)
            .child(memberId)
            .set(json);

        await _db
            .ref(AppConstants.familyList)
            .child(member.familyName)
            .set(member.familyName);

        await _db
            .ref(AppConstants.userFamilyName)
            .child(member.mobile)
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
