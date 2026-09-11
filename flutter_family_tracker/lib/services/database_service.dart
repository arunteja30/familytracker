import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_constants.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../models/registration_model.dart';
import 'geocoding_service.dart';

class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Cache of last saved history point per mobile to avoid redundant DB reads
  static final Map<String, LocationDetailsModel> _lastSavedHistoryPoints = {};
  static final Map<String, String> _lastSavedHistoryKeys = {};

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

    try {
      // 1. Check familyMembersList
      final snap1 = await _db.ref(AppConstants.familyMemberList).get();
      if (snap1.exists && snap1.value != null) {
        for (var m in parseMembersFromSnapshot(snap1.value)) {
          final key = '${m.mobile}_${m.familyName}';
          if (!seen.contains(key) && m.mobile.isNotEmpty) {
            seen.add(key);
            all.add(m);
          }
        }
      }

      // 2. Check familyNames
      final snap2 = await _db.ref(AppConstants.familyDbName).get();
      if (snap2.exists && snap2.value != null) {
        for (var m in parseMembersFromSnapshot(snap2.value)) {
          final key = '${m.mobile}_${m.familyName}';
          if (!seen.contains(key) && m.mobile.isNotEmpty) {
            seen.add(key);
            all.add(m);
          }
        }
      }

      // 3. Check legacy FamilyDetails
      final snap3 = await _db.ref(AppConstants.legacyFamilyDb).get();
      if (snap3.exists && snap3.value != null) {
        for (var m in parseMembersFromSnapshot(snap3.value)) {
          final key = '${m.mobile}_${m.familyName}';
          if (!seen.contains(key) && m.mobile.isNotEmpty) {
            seen.add(key);
            all.add(m);
          }
        }
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

  // Save Location to Realtime DB & History (Resolves Address at Save Time & Filters <200m Duplicates)
  Future<void> saveLocation(
      String mobile, LocationDetailsModel location) async {
    try {
      // 1. Resolve human-readable address on save if missing or placeholder
      if (location.latitude != 0.0 && location.longitude != 0.0) {
        if (location.address.isEmpty ||
            location.address.startsWith('Lat:') ||
            location.address.contains('null')) {
          try {
            final resolved = await GeocodingService.getAddressFromCoordinates(
              location.latitude,
              location.longitude,
            );
            if (resolved.isNotEmpty && !resolved.startsWith('Lat:')) {
              location.address = resolved;
            }
          } catch (_) {}
        }
      }

      final json = location.toJson();
      final clean = mobile.replaceAll(RegExp(r'[^0-9+]'), '');

      // 2. Always update live location nodes
      await _db.ref('locationList').child(mobile).set(json);
      await _db.ref('LocationDetails').child(mobile).set(json);
      if (clean != mobile && clean.isNotEmpty) {
        await _db.ref('locationList').child(clean).set(json);
        await _db.ref('LocationDetails').child(clean).set(json);
      }

      // 3. Save to locationHistory with 200-meter stationary filter
      if (location.date.isNotEmpty && location.latitude != 0.0 && location.longitude != 0.0) {
        final dateKey = location.date;
        final cleanKey = clean.isNotEmpty ? clean : mobile;

        LocationDetailsModel? lastPoint = _lastSavedHistoryPoints[cleanKey];
        String? lastKey = _lastSavedHistoryKeys[cleanKey];

        // If not in in-memory cache, query the most recent history entry for today
        if (lastPoint == null || lastKey == null) {
          try {
            final lastSnap = await _db
                .ref('locationHistory')
                .child(cleanKey)
                .child(dateKey)
                .limitToLast(1)
                .get();
            if (lastSnap.exists && lastSnap.value is Map) {
              final map = lastSnap.value as Map;
              if (map.isNotEmpty) {
                final k = map.keys.first.toString();
                final v = map[k];
                if (v is Map) {
                  lastPoint = LocationDetailsModel.fromJson(v);
                  lastKey = k;
                  _lastSavedHistoryPoints[cleanKey] = lastPoint;
                  _lastSavedHistoryKeys[cleanKey] = lastKey;
                }
              }
            }
          } catch (_) {}
        }

        // Check distance against the previous location record
        bool isDuplicateOrStationary = false;
        if (lastPoint != null && lastKey != null && lastPoint.date == dateKey) {
          final distance = Geolocator.distanceBetween(
            lastPoint.latitude,
            lastPoint.longitude,
            location.latitude,
            location.longitude,
          );
          if (distance < 200.0) {
            isDuplicateOrStationary = true;
          }
        }

        if (isDuplicateOrStationary && lastKey != null) {
          // UPDATE TIME ONLY on existing card, DO NOT add extra card
          final updateData = {
            'timeStamp': location.timeStamp > 0
                ? location.timeStamp
                : DateTime.now().millisecondsSinceEpoch,
            'batteryPercentage': location.batteryPercentage,
            if (location.address.isNotEmpty && !location.address.startsWith('Lat:'))
              'address': location.address,
            if (location.gpsStatus.isNotEmpty) 'gpsStatus': location.gpsStatus,
          };

          await _db.ref('locationHistory').child(mobile).child(dateKey).child(lastKey).update(updateData);
          await _db.ref('LocationHistory').child(mobile).child(dateKey).child(lastKey).update(updateData);
          if (clean != mobile && clean.isNotEmpty) {
            await _db.ref('locationHistory').child(clean).child(dateKey).child(lastKey).update(updateData);
            await _db.ref('LocationHistory').child(clean).child(dateKey).child(lastKey).update(updateData);
          }

          // Update memory cache
          lastPoint?.timeStamp = location.timeStamp;
          if (location.address.isNotEmpty) lastPoint?.address = location.address;
          lastPoint?.batteryPercentage = location.batteryPercentage;
        } else {
          // Distance changed >= 200m or new day: Record new history card
          final timeKey = location.timeStamp > 0
              ? location.timeStamp.toString()
              : DateTime.now().millisecondsSinceEpoch.toString();

          await _db.ref('locationHistory').child(mobile).child(dateKey).child(timeKey).set(json);
          await _db.ref('LocationHistory').child(mobile).child(dateKey).child(timeKey).set(json);
          if (clean != mobile && clean.isNotEmpty) {
            await _db.ref('locationHistory').child(clean).child(dateKey).child(timeKey).set(json);
            await _db.ref('LocationHistory').child(clean).child(dateKey).child(timeKey).set(json);
          }

          _lastSavedHistoryPoints[cleanKey] = location;
          _lastSavedHistoryKeys[cleanKey] = timeKey;
        }
      }
    } catch (e) {
      debugPrint('[FamilyTracker] saveLocation error: $e');
    }
  }

  // Get Location History for a Date with deep multi-path matching & 200m sequential collapsing
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

      // 3. Collapse sequential duplicate / < 200m stationary stays into a single card with latest time
      final List<LocationDetailsModel> collapsed = [];
      for (final p in sorted) {
        if (p.latitude == 0.0 && p.longitude == 0.0) continue;

        if (collapsed.isEmpty) {
          collapsed.add(p);
        } else {
          final last = collapsed.last;
          final dist = Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            p.latitude,
            p.longitude,
          );

          if (dist < 200.0) {
            // Duplicate location or < 200m change: update time only, do not add extra card
            last.timeStamp = p.timeStamp;
            if (p.address.isNotEmpty && (last.address.isEmpty || last.address.startsWith('Lat:'))) {
              last.address = p.address;
            }
            last.batteryPercentage = p.batteryPercentage;
            if (p.gpsStatus.isNotEmpty) last.gpsStatus = p.gpsStatus;
          } else {
            collapsed.add(p);
          }
        }
      }

      return collapsed;
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

  // Clear Location History for a Member (Specific Date or All History)
  Future<void> clearLocationHistory(String mobile, {String? date}) async {
    final clean = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
    final phoneCandidates = {mobile, clean, if (last10.isNotEmpty) last10, '+$clean'};
    final tableCandidates = ['locationHistory', 'LocationHistory', 'location_history'];

    for (var table in tableCandidates) {
      for (var phone in phoneCandidates) {
        if (phone.isEmpty) continue;
        try {
          if (date != null && date.isNotEmpty) {
            await _db.ref(table).child(phone).child(date).remove();
          } else {
            await _db.ref(table).child(phone).remove();
          }
        } catch (_) {}
      }
    }
  }
}
