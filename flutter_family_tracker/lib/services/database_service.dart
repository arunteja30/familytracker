import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_constants.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../models/registration_model.dart';
import '../models/chat_message_model.dart';
import '../models/app_update_model.dart';
import '../models/geofence_place_model.dart';
import '../models/place_event_model.dart';
import '../models/alert_item_model.dart';
import '../utils/phone_utils.dart';
import 'geocoding_service.dart';

class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Cache of last saved history point per mobile to avoid redundant DB reads
  static final Map<String, LocationDetailsModel> _lastSavedHistoryPoints = {};
  static final Map<String, String> _lastSavedHistoryKeys = {};

  // Helper: Normalize & Match Phone Numbers (e.g. +919876543210 vs 9876543210)
  static final RegExp _nonDigitsRegex = RegExp(r'\D');
  static final Map<String, String> _normalizedPhoneCache = {};

  static String normalizePhone(String p) {
    if (p.isEmpty) return '';
    final cached = _normalizedPhoneCache[p];
    if (cached != null) return cached;
    final digits = p.replaceAll(_nonDigitsRegex, '');
    final normalized = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    if (_normalizedPhoneCache.length > 500) {
      _normalizedPhoneCache.clear();
    }
    _normalizedPhoneCache[p] = normalized;
    return normalized;
  }

  static bool matchPhones(String p1, String p2) {
    if (p1.isEmpty || p2.isEmpty) return false;
    if (identical(p1, p2) || p1 == p2) return true;
    final n1 = normalizePhone(p1);
    final n2 = normalizePhone(p2);
    if (n1.isEmpty || n2.isEmpty) return false;
    return n1 == n2;
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
      final snap1 = await _db.ref(AppConstants.familyMemberList).get().timeout(const Duration(seconds: 4));
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
      final snap2 = await _db.ref(AppConstants.familyDbName).get().timeout(const Duration(seconds: 4));
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
      final snap3 = await _db.ref(AppConstants.legacyFamilyDb).get().timeout(const Duration(seconds: 4));
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

  // Find all Family Groups associated with a Phone Number (Fast O(1) Index Lookup with Legacy Fallback)
  Future<List<String>> getFamilyNamesForPhone(String mobile) async {
    final Set<String> groups = {};
    final norm = PhoneUtils.normalize(mobile);

    // 1. Fast O(1) direct index lookup from user_families/{normalizedPhone}
    if (norm.isNotEmpty) {
      try {
        final snap = await _db.ref('user_families').child(norm).get().timeout(const Duration(seconds: 3));
        if (snap.exists && snap.value is Map) {
          (snap.value as Map).forEach((k, v) {
            if (k != null && k.toString().trim().isNotEmpty) {
              groups.add(k.toString().trim());
            }
          });
          if (groups.isNotEmpty) {
            debugPrint('[FamilyTracker] ⚡ Fast index lookup found ${groups.length} groups for $norm');
            return groups.toList();
          }
        }
      } catch (e) {
        debugPrint('[FamilyTracker] Index lookup bypassed: $e');
      }
    }

    // 2. Fallback: Search all members for legacy backwards-compatibility
    final allMembers = await getAllDatabaseMembers();
    debugPrint('[FamilyTracker] Searching groups for phone: $mobile among ${allMembers.length} members');

    for (var member in allMembers) {
      if (PhoneUtils.isSame(member.mobile, mobile) && member.familyName.trim().isNotEmpty) {
        final fam = member.familyName.trim();
        groups.add(fam);
        // Auto-index into user_families for future instant lookups
        if (norm.isNotEmpty) {
          _db.ref('user_families').child(norm).child(fam).set(true).catchError((_) {});
        }
      }
    }

    // Check UserFamilyName node fallback
    if (groups.isEmpty) {
      try {
        final snap = await _db.ref(AppConstants.userFamilyName).child(mobile).get().timeout(const Duration(seconds: 3));
        if (snap.exists && snap.value != null) {
          final fam = snap.value.toString().trim();
          groups.add(fam);
          if (norm.isNotEmpty) {
            _db.ref('user_families').child(norm).child(fam).set(true).catchError((_) {});
          }
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

  // Stream of Real-time Location for a Specific Mobile Number (Multi-format broadcast stream)
  Stream<LocationDetailsModel?> streamLocationDetails(String mobile) {
    final candidates = <String>{
      mobile,
      mobile.replaceAll(RegExp(r'[^0-9+]'), ''),
      mobile.replaceAll(RegExp(r'\D'), ''),
    };
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      final last10 = digits.substring(digits.length - 10);
      candidates.add(last10);
      candidates.add('+91$last10');
      candidates.add('91$last10');
    }
    candidates.removeWhere((c) => c.isEmpty);

    late StreamController<LocationDetailsModel?> controller;
    final subscriptions = <StreamSubscription>[];

    controller = StreamController<LocationDetailsModel?>.broadcast(
      onListen: () {
        // Emit current initial value immediately so UI has markers right away
        getLocationDetails(mobile).then((loc) {
          if (!controller.isClosed && loc != null) {
            controller.add(loc);
          }
        }).catchError((_) {});

        for (final phone in candidates) {
          subscriptions.add(
            _db.ref(AppConstants.locationList).child(phone).onValue.listen((event) {
              final data = event.snapshot.value;
              if (data != null && data is Map && !controller.isClosed) {
                controller.add(LocationDetailsModel.fromJson(data));
              }
            }, onError: (_) {}),
          );
          subscriptions.add(
            _db.ref(AppConstants.legacyLocationList).child(phone).onValue.listen((event) {
              final data = event.snapshot.value;
              if (data != null && data is Map && !controller.isClosed) {
                controller.add(LocationDetailsModel.fromJson(data));
              }
            }, onError: (_) {}),
          );
        }
      },
      onCancel: () {
        for (final sub in subscriptions) {
          sub.cancel();
        }
        subscriptions.clear();
      },
    );

    return controller.stream;
  }

  // Get Location Details Once (with phone format fallback & legacy node support)
  Future<LocationDetailsModel?> getLocationDetails(String mobile) async {
    try {
      final candidates = <String>{
        mobile,
        mobile.replaceAll(RegExp(r'[^0-9+]'), ''),
        mobile.replaceAll(RegExp(r'\D'), ''),
      };
      final digits = mobile.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        final last10 = digits.substring(digits.length - 10);
        candidates.add(last10);
        candidates.add('+91$last10');
        candidates.add('91$last10');
      }

      for (final phone in candidates) {
        if (phone.isEmpty) continue;
        var snapshot = await _db.ref(AppConstants.locationList).child(phone).get();
        if (snapshot.exists && snapshot.value is Map) {
          return LocationDetailsModel.fromJson(snapshot.value as Map);
        }
        var legacySnap = await _db.ref(AppConstants.legacyLocationList).child(phone).get();
        if (legacySnap.exists && legacySnap.value is Map) {
          return LocationDetailsModel.fromJson(legacySnap.value as Map);
        }
      }
      return null;
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

        // Fast O(1) Index mapping: user_families/{normalizedMobile}/{familyName} = true
        final norm = PhoneUtils.normalize(member.mobile);
        if (norm.isNotEmpty) {
          await _db
              .ref('user_families')
              .child(norm)
              .child(member.familyName)
              .set(true);

          await _db
              .ref('family_members')
              .child(member.familyName)
              .child(norm)
              .set(json);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // Peer-to-Peer Emergency SOS Alert Methods ($0 Cost, No Cloud Functions)
  // -------------------------------------------------------------

  /// Broadcast an Emergency SOS panic event to all members of a family circle
  Future<void> triggerFamilySos({
    required String familyName,
    required String senderPhone,
    required String senderName,
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    if (familyName.trim().isEmpty) return;
    try {
      final rawKey = familyName.trim();
      final cleanKey = rawKey.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      final normalizedPhone = PhoneUtils.normalize(senderPhone);
      final effectivePhone = normalizedPhone.isNotEmpty ? normalizedPhone : senderPhone;
      final effectiveName = senderName.trim().isNotEmpty ? senderName.trim() : 'Family Member';
      final now = DateTime.now().millisecondsSinceEpoch;

      final alertData = {
        'senderPhone': effectivePhone,
        'senderName': effectiveName,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'timestamp': now,
        'status': 'ACTIVE',
      };

      // Set active alert on primary key
      await _db.ref('emergency_alerts').child(cleanKey).set(alertData);
      if (rawKey != cleanKey) {
        await _db.ref('emergency_alerts').child(rawKey).set(alertData);
      }

      // Record in emergency history log
      try {
        await _db.ref('emergency_history').child(cleanKey).child(now.toString()).set(alertData);
      } catch (_) {}

      debugPrint('[FamilyTracker] 🚨 SOS Alert broadcasted for family $cleanKey ($effectiveName at $latitude,$longitude - $address)');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to broadcast SOS: $e');
    }
  }

  /// Dismiss / Resolve an active Emergency SOS alert
  Future<void> clearFamilySos(String familyName) async {
    if (familyName.trim().isEmpty) return;
    try {
      final rawKey = familyName.trim();
      final cleanKey = rawKey.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      await _db.ref('emergency_alerts').child(cleanKey).remove();
      if (rawKey != cleanKey) {
        await _db.ref('emergency_alerts').child(rawKey).remove();
      }
      debugPrint('[FamilyTracker] SOS Alert dismissed for family $cleanKey');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to clear SOS: $e');
    }
  }

  /// Stream active Emergency SOS alerts for the current family circle
  Stream<Map<String, dynamic>?> streamEmergencyAlerts(String familyName) {
    if (familyName.trim().isEmpty) return const Stream.empty();
    final cleanKey = familyName.trim().replaceAll(RegExp(r'[.#$\[\]]'), '_');
    return _db.ref('emergency_alerts').child(cleanKey).onValue.map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        return Map<String, dynamic>.from(val);
      }
      return null;
    });
  }

  /// Broadcast a peace-of-mind Check-In ("I'm Safe") event to the family circle
  Future<void> broadcastCheckIn({
    required String familyName,
    required String senderName,
    required String senderPhone,
    double? latitude,
    double? longitude,
    String? address,
    String? customNote,
  }) async {
    if (familyName.trim().isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final effectiveName = senderName.trim().isNotEmpty ? senderName.trim() : 'Family Member';
      final note = customNote != null && customNote.trim().isNotEmpty ? ': "$customNote"' : '';

      final alert = AlertItemModel(
        id: '',
        familyName: familyName.trim(),
        type: AlertType.checkIn,
        title: '✅ $effectiveName Checked In Safely',
        body: '$effectiveName ($senderPhone) marked themselves safe$note.',
        memberName: effectiveName,
        memberMobile: senderPhone,
        timestamp: now,
        latitude: latitude,
        longitude: longitude,
        extraInfo: address ?? '',
      );

      await logAlert(alert);
      debugPrint('[DatabaseService] ✅ Check-In logged for $effectiveName');
    } catch (e) {
      debugPrint('[DatabaseService] Failed to broadcast Check-In: $e');
    }
  }

  // Deduplication cache for low battery warnings (memberMobile -> lastAlertTimestamp)
  static final Map<String, int> _lastBatteryAlertTimestamps = {};

  /// Broadcast a low battery peer warning (throttled to once per 4 hours per device)
  Future<void> broadcastLowBatteryAlert({
    required String familyName,
    required String memberName,
    required String memberMobile,
    required int batteryLevel,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    if (familyName.trim().isEmpty || batteryLevel > 15 || batteryLevel <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAlert = _lastBatteryAlertTimestamps[memberMobile] ?? 0;
    // 4 hours cooldown
    if (now - lastAlert < 4 * 60 * 60 * 1000) return;

    try {
      _lastBatteryAlertTimestamps[memberMobile] = now;
      final effectiveName = memberName.trim().isNotEmpty ? memberName.trim() : 'Family Member';

      final alert = AlertItemModel(
        id: '',
        familyName: familyName.trim(),
        type: AlertType.batteryLow,
        title: '⚡ Low Battery Warning: $effectiveName',
        body: '$effectiveName\'s device is at $batteryLevel% battery and may go offline soon.',
        memberName: effectiveName,
        memberMobile: memberMobile,
        timestamp: now,
        latitude: latitude,
        longitude: longitude,
        extraInfo: address ?? '',
      );

      await logAlert(alert);
      debugPrint('[DatabaseService] ⚡ Low battery alert broadcasted for $effectiveName ($batteryLevel%)');
    } catch (e) {
      debugPrint('[DatabaseService] Failed to broadcast low battery alert: $e');
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

  // =========================================================================
  // 💬 FAMILY CIRCLE REAL-TIME GROUP CHAT (100% Free Tier, $0 Backend Cost)
  // =========================================================================

  /// Send a text or interactive location message to the family circle
  Future<void> sendChatMessage(String familyName, ChatMessageModel message) async {
    if (familyName.isEmpty) return;
    try {
      final cleanFamily = familyName.trim();
      final ref = _db.ref('family_chats').child(cleanFamily).push();
      await ref.set(message.toJson());
      debugPrint('[FamilyTracker] 💬 Chat message sent to $cleanFamily');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to send chat message: $e');
      rethrow;
    }
  }

  static const int chatMessageTtlMs = 24 * 60 * 60 * 1000; // 24 Hours

  /// Real-time stream of latest messages for active family circle (Auto-purging > 24 hours old)
  Stream<List<ChatMessageModel>> streamChatMessages(String familyName, {int limit = 100}) {
    if (familyName.isEmpty) return Stream.value([]);
    final cleanFamily = familyName.trim();
    return _db
        .ref('family_chats')
        .child(cleanFamily)
        .limitToLast(limit)
        .onValue
        .map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return <ChatMessageModel>[];
      }
      final data = snapshot.value as Map;
      final List<ChatMessageModel> messages = [];
      final List<String> expiredMessageIds = [];
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int cutoff = now - chatMessageTtlMs;

      data.forEach((key, val) {
        if (val is Map) {
          try {
            final msg = ChatMessageModel.fromJson(key.toString(), val);
            if (msg.timestamp >= cutoff) {
              messages.add(msg);
            } else {
              expiredMessageIds.add(msg.messageId);
            }
          } catch (_) {}
        }
      });

      // Silently auto-purge expired messages from Firebase RTDB in background ($0 Spark Tier optimization)
      if (expiredMessageIds.isNotEmpty) {
        deleteChatMessages(cleanFamily, expiredMessageIds);
      }

      // Sort in chronological order (oldest first for scrolling down)
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    });
  }

  /// Edit a single chat message in family group
  Future<void> editChatMessage(String familyName, String messageId, String newText) async {
    if (familyName.isEmpty || messageId.isEmpty || newText.trim().isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.ref('family_chats').child(familyName.trim()).child(messageId).update({
        'text': newText.trim(),
        'isEdited': true,
        'editedTimestamp': now,
      });
      debugPrint('[FamilyTracker] ✏️ Chat message $messageId edited in $familyName');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to edit chat message: $e');
      rethrow;
    }
  }

  /// Delete a single chat message
  Future<void> deleteChatMessage(String familyName, String messageId) async {
    if (familyName.isEmpty || messageId.isEmpty) return;
    try {
      await _db.ref('family_chats').child(familyName.trim()).child(messageId).remove();
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to delete chat message: $e');
    }
  }

  /// Delete multiple chat messages in batch
  Future<void> deleteChatMessages(String familyName, List<String> messageIds) async {
    if (familyName.isEmpty || messageIds.isEmpty) return;
    try {
      final Map<String, Object?> updates = {};
      for (final id in messageIds) {
        if (id.isNotEmpty) {
          updates['family_chats/${familyName.trim()}/$id'] = null;
        }
      }
      if (updates.isNotEmpty) {
        await _db.ref().update(updates);
        debugPrint('[FamilyTracker] 🗑️ Deleted ${messageIds.length} messages in $familyName');
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to batch delete chat messages: $e');
      // Fallback to sequential deletion
      for (final id in messageIds) {
        await deleteChatMessage(familyName, id);
      }
    }
  }

  // =========================================================================
  // 👤 1-ON-1 DIRECT CHAT (Between Two Individual Family Members)
  // =========================================================================

  /// Generate a symmetric room ID for two phone numbers
  static String getDirectChatRoomId(String phone1, String phone2) {
    final p1 = PhoneUtils.normalize(phone1);
    final p2 = PhoneUtils.normalize(phone2);
    final list = [p1, p2]..sort();
    return '${list[0]}__${list[1]}';
  }

  /// Send a 1-on-1 direct chat message
  Future<void> sendDirectChatMessage(String roomId, ChatMessageModel message) async {
    if (roomId.isEmpty) return;
    try {
      final ref = _db.ref('direct_chats').child(roomId).push();
      await ref.set(message.toJson());
      debugPrint('[FamilyTracker] 👤 Direct chat message sent to $roomId');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to send direct chat message: $e');
      rethrow;
    }
  }

  /// Edit a 1-on-1 direct chat message
  Future<void> editDirectChatMessage(String roomId, String messageId, String newText) async {
    if (roomId.isEmpty || messageId.isEmpty || newText.trim().isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.ref('direct_chats').child(roomId).child(messageId).update({
        'text': newText.trim(),
        'isEdited': true,
        'editedTimestamp': now,
      });
      debugPrint('[FamilyTracker] ✏️ Direct chat message $messageId edited in $roomId');
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to edit direct chat message: $e');
      rethrow;
    }
  }

  /// Stream 1-on-1 direct chat messages (Auto-purging > 24 hours old)
  Stream<List<ChatMessageModel>> streamDirectChatMessages(String roomId, {int limit = 100}) {
    if (roomId.isEmpty) return Stream.value([]);
    return _db
        .ref('direct_chats')
        .child(roomId)
        .limitToLast(limit)
        .onValue
        .map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) {
        return <ChatMessageModel>[];
      }
      final data = snapshot.value as Map;
      final List<ChatMessageModel> messages = [];
      final List<String> expiredMessageIds = [];
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int cutoff = now - chatMessageTtlMs;

      data.forEach((key, val) {
        if (val is Map) {
          try {
            final msg = ChatMessageModel.fromJson(key.toString(), val);
            if (msg.timestamp >= cutoff) {
              messages.add(msg);
            } else {
              expiredMessageIds.add(msg.messageId);
            }
          } catch (_) {}
        }
      });

      // Silently auto-purge expired direct messages from Firebase RTDB in background
      if (expiredMessageIds.isNotEmpty) {
        deleteDirectChatMessages(roomId, expiredMessageIds);
      }

      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    });
  }

  /// Delete a single 1-on-1 chat message
  Future<void> deleteDirectChatMessage(String roomId, String messageId) async {
    if (roomId.isEmpty || messageId.isEmpty) return;
    try {
      await _db.ref('direct_chats').child(roomId).child(messageId).remove();
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to delete direct chat message: $e');
    }
  }

  /// Delete multiple 1-on-1 chat messages in batch
  Future<void> deleteDirectChatMessages(String roomId, List<String> messageIds) async {
    if (roomId.isEmpty || messageIds.isEmpty) return;
    try {
      final Map<String, Object?> updates = {};
      for (final id in messageIds) {
        if (id.isNotEmpty) {
          updates['direct_chats/$roomId/$id'] = null;
        }
      }
      if (updates.isNotEmpty) {
        await _db.ref().update(updates);
        debugPrint('[FamilyTracker] 🗑️ Deleted ${messageIds.length} direct messages in $roomId');
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to batch delete direct messages: $e');
      for (final id in messageIds) {
        await deleteDirectChatMessage(roomId, id);
      }
    }
  }

  // 🚀 APP UPDATE MANAGEMENT (Realtime Database 'UpdateData')

  /// Stream app update metadata in real-time from RTDB node 'UpdateData'
  Stream<AppUpdateModel?> streamAppUpdate() {
    return _db.ref(AppConstants.mandatoryData).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return null;
      }
      if (snapshot.value is Map) {
        return AppUpdateModel.fromMap(snapshot.value as Map);
      }
      return null;
    });
  }

  /// Get app update metadata once from RTDB node 'UpdateData'
  Future<AppUpdateModel?> getAppUpdate() async {
    try {
      final snapshot = await _db.ref(AppConstants.mandatoryData).get().timeout(const Duration(seconds: 3));
      if (snapshot.exists && snapshot.value is Map) {
        return AppUpdateModel.fromMap(snapshot.value as Map);
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Error fetching UpdateData: $e');
    }
    return null;
  }

  /// Save or update UpdateData node in RTDB
  Future<void> setAppUpdate(AppUpdateModel update) async {
    try {
      await _db.ref(AppConstants.mandatoryData).set(update.toMap());
      debugPrint('[FamilyTracker] ✅ UpdateData successfully updated in RTDB');
    } catch (e) {
      debugPrint('[FamilyTracker] Error setting UpdateData: $e');
    }
  }

  // 📧 ANTI-THEFT EMAIL CONFIGURATION (Realtime Database 'EmailConfig')

  /// Stream email config in real-time from RTDB
  Stream<Map<String, dynamic>?> streamEmailConfig() {
    return _db.ref('EmailConfig').onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  /// Get email config from RTDB ('EmailConfig' or 'AppConfig/EmailConfig')
  Future<Map<String, dynamic>?> getEmailConfig() async {
    try {
      final snap = await _db.ref('EmailConfig').get();
      if (snap.exists && snap.value is Map) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
      final snap2 = await _db.ref('AppConfig/EmailConfig').get();
      if (snap2.exists && snap2.value is Map) {
        return Map<String, dynamic>.from(snap2.value as Map);
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Error fetching EmailConfig: $e');
    }
    return null;
  }

  /// Save email config directly to Firebase RTDB node 'EmailConfig'
  Future<void> setEmailConfig({
    required String senderEmail,
    required String appPassword,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'senderEmail': senderEmail.trim(),
        'appPassword': appPassword.trim().replaceAll(' ', ''),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await _db.ref('EmailConfig').update(data);
      debugPrint('[FamilyTracker] ✅ Server EmailConfig saved to RTDB /EmailConfig');
    } catch (e) {
      debugPrint('[FamilyTracker] Error setting EmailConfig in RTDB: $e');
    }
  }

  /// Save individual user alert email to their profile node in RTDB
  Future<void> saveUserAlertEmail(String mobile, String alertEmail) async {
    if (mobile.isEmpty || alertEmail.isEmpty) return;
    final norm = PhoneUtils.normalize(mobile);
    try {
      await _db.ref(AppConstants.registrationDetails).child(norm).update({
        'alertEmail': alertEmail.trim(),
      });
      await _db.ref(AppConstants.userList).child(norm).update({
        'alertEmail': alertEmail.trim(),
      });
      debugPrint('[FamilyTracker] ✅ User alert email saved to profile in RTDB: $norm -> $alertEmail');
    } catch (e) {
      debugPrint('[FamilyTracker] Error saving user alertEmail: $e');
    }
  }

  /// Fetch individual user alert email from their profile node in RTDB
  Future<String?> getUserAlertEmail(String mobile) async {
    if (mobile.isEmpty) return null;
    final norm = PhoneUtils.normalize(mobile);
    try {
      final snap = await _db.ref(AppConstants.registrationDetails).child(norm).child('alertEmail').get();
      if (snap.exists && snap.value != null && snap.value.toString().isNotEmpty) {
        return snap.value.toString().trim();
      }
      final snap2 = await _db.ref(AppConstants.userList).child(norm).child('alertEmail').get();
      if (snap2.exists && snap2.value != null && snap2.value.toString().isNotEmpty) {
        return snap2.value.toString().trim();
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Error fetching user alertEmail: $e');
    }
    return null;
  }

  // ===========================================================================
  // SMART PLACES & GEOFENCING SAFE ZONES
  // ===========================================================================

  /// Stream of safe places configured for a given family group
  Stream<List<GeofencePlaceModel>> streamFamilyPlaces(String familyName) {
    final cleanGroup = familyName.trim();
    if (cleanGroup.isEmpty) return Stream.value([]);

    return _db.ref('Places').child(cleanGroup).onValue.map((event) {
      final List<GeofencePlaceModel> places = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            places.add(GeofencePlaceModel.fromJson(val, key.toString()));
          }
        });
      }
      places.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return places;
    }).handleError((err) {
      debugPrint('[DatabaseService] Places stream handled safely: $err');
      return <GeofencePlaceModel>[];
    });
  }

  /// Fetch all places once for a family
  Future<List<GeofencePlaceModel>> getFamilyPlaces(String familyName) async {
    final cleanGroup = familyName.trim();
    if (cleanGroup.isEmpty) return [];

    try {
      final snap = await _db.ref('Places').child(cleanGroup).get();
      final List<GeofencePlaceModel> places = [];
      final data = snap.value;
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            places.add(GeofencePlaceModel.fromJson(val, key.toString()));
          }
        });
      }
      return places;
    } catch (e) {
      debugPrint('[DatabaseService] Error fetching family places: $e');
      return [];
    }
  }

  /// Save or update a safe place
  Future<bool> savePlace(GeofencePlaceModel place) async {
    if (place.familyName.trim().isEmpty) return false;
    try {
      final ref = place.id.isNotEmpty
          ? _db.ref('Places').child(place.familyName.trim()).child(place.id)
          : _db.ref('Places').child(place.familyName.trim()).push();

      if (place.id.isEmpty) {
        place.id = ref.key ?? '';
      }

      await ref.set(place.toJson());
      debugPrint('[DatabaseService] ✅ Place saved successfully: ${place.name} (${place.id})');
      return true;
    } catch (e) {
      debugPrint('[DatabaseService] Error saving place: $e');
      return false;
    }
  }

  /// Delete a safe place
  Future<bool> deletePlace(String familyName, String placeId) async {
    if (familyName.trim().isEmpty || placeId.trim().isEmpty) return false;
    try {
      await _db.ref('Places').child(familyName.trim()).child(placeId.trim()).remove();
      debugPrint('[DatabaseService] 🗑️ Place deleted: $placeId from $familyName');
      return true;
    } catch (e) {
      debugPrint('[DatabaseService] Error deleting place: $e');
      return false;
    }
  }

  /// Log a place arrival/departure event to RTDB
  Future<void> logPlaceEvent(PlaceEventModel event) async {
    if (event.familyName.trim().isEmpty) return;
    try {
      final ref = _db.ref('PlaceEvents').child(event.familyName.trim()).push();
      event.id = ref.key ?? '';
      await ref.set(event.toJson());
      debugPrint('[DatabaseService] 📍 Place event logged: ${event.memberName} ${event.eventType} ${event.placeName}');
    } catch (e) {
      debugPrint('[DatabaseService] Error logging place event: $e');
    }
  }

  /// Stream recent place events for a family circle
  Stream<List<PlaceEventModel>> streamRecentPlaceEvents(String familyName, {int limit = 30}) {
    final cleanGroup = familyName.trim();
    if (cleanGroup.isEmpty) return Stream.value([]);

    return _db.ref('PlaceEvents').child(cleanGroup).limitToLast(limit).onValue.map((event) {
      final List<PlaceEventModel> events = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            events.add(PlaceEventModel.fromJson(val, key.toString()));
          }
        });
      }
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return events;
    }).handleError((err) {
      debugPrint('[DatabaseService] PlaceEvents stream handled safely: $err');
      return <PlaceEventModel>[];
    });
  }

  // ===========================================================================
  // CENTRALIZED ALERTS FEED & 24-HOUR AUTO-PURGE
  // ===========================================================================

  /// Log any safety alert (SOS, Intruder, Place Geofence, Battery) to RTDB
  Future<void> logAlert(AlertItemModel alert) async {
    if (alert.familyName.trim().isEmpty) return;
    try {
      final ref = _db.ref('Alerts').child(alert.familyName.trim()).push();
      final alertToSave = AlertItemModel(
        id: ref.key ?? '',
        familyName: alert.familyName,
        type: alert.type,
        title: alert.title,
        body: alert.body,
        memberName: alert.memberName,
        memberMobile: alert.memberMobile,
        timestamp: alert.timestamp,
        latitude: alert.latitude,
        longitude: alert.longitude,
        placeName: alert.placeName,
        extraInfo: alert.extraInfo,
      );
      await ref.set(alertToSave.toJson());
      debugPrint('[DatabaseService] 🔔 Alert logged: [${alert.type.name}] ${alert.title}');
    } catch (e) {
      debugPrint('[DatabaseService] Error logging alert: $e');
    }
  }

  /// Stream active alerts for a family with 24-hour self-delete & server cleanup
  Stream<List<AlertItemModel>> streamFamilyAlerts(String familyName) {
    final cleanGroup = familyName.trim();
    if (cleanGroup.isEmpty) return Stream.value([]);

    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff24h = now - AlertItemModel.ttlMilliseconds;

    return _db.ref('Alerts').child(cleanGroup).onValue.map((event) {
      final List<AlertItemModel> validAlerts = [];
      final List<String> expiredKeys = [];
      final data = event.snapshot.value;

      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            final item = AlertItemModel.fromJson(val, key.toString());
            if (item.timestamp < cutoff24h) {
              expiredKeys.add(key.toString());
            } else {
              validAlerts.add(item);
            }
          }
        });
      }

      // Automatically purge expired alerts older than 24 hours from Firebase RTDB
      if (expiredKeys.isNotEmpty) {
        _purgeExpiredAlerts(cleanGroup, expiredKeys);
      }

      validAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return validAlerts;
    }).handleError((err) {
      debugPrint('[DatabaseService] Alerts stream handled safely: $err');
      return <AlertItemModel>[];
    });
  }

  void _purgeExpiredAlerts(String familyName, List<String> expiredKeys) {
    Future.microtask(() async {
      for (final key in expiredKeys) {
        try {
          await _db.ref('Alerts').child(familyName).child(key).remove();
        } catch (_) {}
      }
      debugPrint('[DatabaseService] 🧹 Purged ${expiredKeys.length} expired (24h+) alerts from $familyName');
    });
  }

  /// Manually clear all alerts for a family
  Future<bool> clearAllAlerts(String familyName) async {
    if (familyName.trim().isEmpty) return false;
    try {
      await _db.ref('Alerts').child(familyName.trim()).remove();
      debugPrint('[DatabaseService] 🗑️ Cleared all alerts for $familyName');
      return true;
    } catch (e) {
      debugPrint('[DatabaseService] Error clearing alerts: $e');
      return false;
    }
  }

  /// Delete a single alert
  Future<bool> deleteAlert(String familyName, String alertId) async {
    if (familyName.trim().isEmpty || alertId.trim().isEmpty) return false;
    try {
      await _db.ref('Alerts').child(familyName.trim()).child(alertId.trim()).remove();
      return true;
    } catch (e) {
      debugPrint('[DatabaseService] Error deleting alert: $e');
      return false;
    }
  }
}
