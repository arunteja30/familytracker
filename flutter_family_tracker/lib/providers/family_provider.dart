import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
import '../services/location_service.dart';
import '../services/native_service.dart';
import '../services/contacts_service.dart';
import '../services/geocoding_service.dart';
import '../services/notification_service.dart';
import '../utils/phone_utils.dart';

class FamilyProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locationService = LocationService();

  String _currentFamilyName = '';
  List<String> _userFamilyGroups = [];
  List<FamilyMemberModel> _familyMembers = [];
  final Map<String, LocationDetailsModel> _memberLocations = {};
  final Set<String> _notifiedLowBatteryMembers = {};
  Map<String, dynamic>? _activeEmergencyAlert;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _membersSubscription;
  StreamSubscription? _emergencySubscription;
  final Map<String, StreamSubscription> _locationSubscriptions = {};

  static String formatFamilyDisplayName(String? name) {
    if (name == null || name.trim().isEmpty) return 'MyFamily';
    // Do not show numbers after _ (e.g. Smith_9876543210 -> Smith, MyFamily_123 -> MyFamily)
    final clean = name.replaceFirst(RegExp(r'_\d+.*$'), '');
    return clean.isNotEmpty ? clean : name;
  }

  String get currentFamilyName =>
      _currentFamilyName.isNotEmpty ? _currentFamilyName : 'MyFamily';
  String get displayFamilyName => formatFamilyDisplayName(_currentFamilyName);
  List<String> get userFamilyGroups => _userFamilyGroups;
  List<FamilyMemberModel> get familyMembers => _familyMembers;
  Map<String, LocationDetailsModel> get memberLocations => _memberLocations;
  Map<String, dynamic>? get activeEmergencyAlert => _activeEmergencyAlert;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Check if current user is Admin of the active family group
  bool isUserAdmin(String userPhone) {
    if (userPhone.trim().isEmpty) return false;

    // 1. If group name suffix is user's phone number (e.g. MyFamily_9876543210)
    if (_currentFamilyName.contains('_')) {
      final parts = _currentFamilyName.split('_');
      if (parts.length >= 2) {
        final phonePart = parts.sublist(1).join('_');
        if (DatabaseService.matchPhones(phonePart, userPhone)) {
          return true;
        }
      }
    }

    // 2. If any member has adminName matching user's phone or user's registered name
    final currentUserName = PreferencesService.getUserName() ?? '';
    for (var m in _familyMembers) {
      if (m.adminName != null && m.adminName!.trim().isNotEmpty) {
        if (DatabaseService.matchPhones(m.adminName!, userPhone) ||
            (currentUserName.isNotEmpty &&
                m.adminName!.trim().toLowerCase() ==
                    currentUserName.trim().toLowerCase())) {
          return true;
        }
      }
      // If user's own record lists relationship as Admin / Creator / Owner / Head
      if (DatabaseService.matchPhones(m.mobile, userPhone)) {
        final rel = m.relationship.trim().toLowerCase();
        if (rel == 'admin' ||
            rel == 'creator' ||
            rel == 'owner' ||
            rel == 'head') {
          return true;
        }
      }
    }

    // 3. If user is the first/creator member in the group
    if (_familyMembers.isNotEmpty &&
        DatabaseService.matchPhones(_familyMembers.first.mobile, userPhone)) {
      return true;
    }

    return false;
  }

  Timer? _notifyDebounceTimer;

  void _safeNotifyListeners({bool immediate = false}) {
    if (immediate) {
      _notifyDebounceTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
      return;
    }

    if (_notifyDebounceTimer?.isActive ?? false) return;
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    });
  }

  // Enrich member names with device contact book names
  List<FamilyMemberModel> _enrichWithContactNames(
      List<FamilyMemberModel> members) {
    try {
      return members.map((m) {
        final contactName = ContactsService.getContactDisplayName(m.mobile, m.name);
        if (contactName.isNotEmpty && contactName != m.name) {
          return FamilyMemberModel(
            name: contactName,
            mobile: m.mobile,
            relationship: m.relationship,
            memberId: m.memberId,
            familyName: m.familyName,
            pushNofityToken: m.pushNofityToken,
            adminName: m.adminName,
            password: m.password,
            message: m.message,
            gpsInfo: m.gpsInfo,
            uid: m.uid,
            isRegistered: m.isRegistered,
          );
        }
        return m;
      }).toList();
    } catch (_) {
      return members;
    }
  }

  // Initialize and Load Data
  Future<void> init(String userPhone) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      debugPrint('[FamilyTracker] Initializing FamilyProvider for: $userPhone');

      // 1. Sync device contacts safely
      try {
        await ContactsService.syncDeviceContacts();
      } catch (e) {
        debugPrint('[FamilyTracker] Contacts error: $e');
      }

      // 2. Fetch all groups on Firebase that this phone is added to
      _userFamilyGroups = await _dbService.getFamilyNamesForPhone(userPhone);
      debugPrint('[FamilyTracker] Detected groups for user: $_userFamilyGroups');

      // 3. Determine best family group to load
      String? savedFamily = PreferencesService.getUserFamilyName();

      if (_userFamilyGroups.isNotEmpty) {
        if (savedFamily != null && _userFamilyGroups.contains(savedFamily)) {
          _currentFamilyName = savedFamily;
        } else {
          _currentFamilyName = _userFamilyGroups.first;
          await PreferencesService.saveUserFamilyName(_currentFamilyName);
        }
      } else if (savedFamily != null && savedFamily.isNotEmpty) {
        _currentFamilyName = savedFamily;
      } else {
        _currentFamilyName = 'MyFamily';
        await PreferencesService.saveUserFamilyName(_currentFamilyName);
      }

      debugPrint('[FamilyTracker] Selected active group: $_currentFamilyName');

      // 4. Fetch initial snapshot directly and enrich with contacts
      final initialMembers = await _dbService.getFamilyMembers(_currentFamilyName);
      _familyMembers = _enrichWithContactNames(initialMembers);
      debugPrint('[FamilyTracker] Initial snapshot loaded: ${_familyMembers.length} members');

      // 5. Subscribe to real-time updates for the active family group
      _subscribeToMembers(_currentFamilyName);
      _subscribeToEmergencyAlerts(_currentFamilyName);

      // 6. Start continuous background location tracking
      try {
        _locationService.startContinuousBackgroundLocationTracking(userPhone);
        await NativeService.startNativeStickyService();
      } catch (e) {
        debugPrint('[FamilyTracker] Location start error: $e');
      }
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[FamilyTracker] Init error: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  // Subscribe to Live Members
  void _subscribeToMembers(String familyName) {
    _membersSubscription?.cancel();
    _membersSubscription =
        _dbService.streamFamilyMembers(familyName).listen((members) {
      _familyMembers = _enrichWithContactNames(members);
      _subscribeToLocations(members);
      _safeNotifyListeners();
    }, onError: (err) {
      debugPrint('[FamilyTracker] Stream members error: $err');
    });
  }

  // Subscribe to Peer-to-Peer Emergency SOS Alerts
  void _subscribeToEmergencyAlerts(String familyName) {
    _emergencySubscription?.cancel();
    if (familyName.isEmpty) return;

    _emergencySubscription =
        _dbService.streamEmergencyAlerts(familyName).listen((alert) {
      _activeEmergencyAlert = alert;
      if (alert != null && alert['status'] == 'ACTIVE') {
        final senderPhone = alert['senderPhone']?.toString() ?? '';
        final myPhone = PreferencesService.getUserPhone() ?? '';
        // Fire heads-up sound & notification if sender is someone else
        if (!PhoneUtils.isSame(senderPhone, myPhone)) {
          NotificationService.showSosAlert(
            senderName: alert['senderName']?.toString() ?? 'Family Member',
            senderPhone: PhoneUtils.formatDisplay(senderPhone),
            address: alert['address']?.toString() ?? '',
          );
        }
      }
      _safeNotifyListeners();
    }, onError: (err) {
      debugPrint('[FamilyTracker] Emergency stream error: $err');
    });
  }

  // Subscribe to Realtime Locations of all Members
  void _subscribeToLocations(List<FamilyMemberModel> members) {
    for (var sub in _locationSubscriptions.values) {
      sub.cancel();
    }
    _locationSubscriptions.clear();

    for (var member in members) {
      if (member.mobile.isNotEmpty) {
        _locationSubscriptions[member.mobile] = _dbService
            .streamLocationDetails(member.mobile)
            .listen((location) {
          if (location != null) {
            _memberLocations[member.mobile] = location;

            // Low Battery Notification trigger
            if (location.batteryPercentage <= 15 && location.batteryPercentage > 0) {
              final myPhone = PreferencesService.getUserPhone() ?? '';
              if (!PhoneUtils.isSame(member.mobile, myPhone) &&
                  !_notifiedLowBatteryMembers.contains(member.mobile)) {
                _notifiedLowBatteryMembers.add(member.mobile);
                NotificationService.showLowBatteryAlert(
                  memberName: member.name.isNotEmpty ? member.name : member.mobile,
                  batteryLevel: location.batteryPercentage,
                );
              }
            } else if (location.batteryPercentage > 20) {
              _notifiedLowBatteryMembers.remove(member.mobile);
            }

            _safeNotifyListeners();
          }
        }, onError: (err) {
          debugPrint('[FamilyTracker] Stream location error for ${member.mobile}: $err');
        });
      }
    }
  }

  // Broadcast SOS Distress Event to all Family Devices
  Future<void> triggerSos({
    double? latitude,
    double? longitude,
    String? address,
    String? senderName,
  }) async {
    final myPhone = PreferencesService.getUserPhone() ?? '';
    final myName = senderName ?? PreferencesService.getUserName() ?? 'Family Member';

    double lat = latitude ?? 0.0;
    double lng = longitude ?? 0.0;
    String addr = address ?? '';

    if (lat == 0.0 && lng == 0.0) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
    }

    if (addr.isEmpty && lat != 0.0) {
      try {
        addr = await GeocodingService.getAddress(lat, lng);
      } catch (_) {}
    }

    await _dbService.triggerFamilySos(
      familyName: currentFamilyName,
      senderPhone: myPhone,
      senderName: myName,
      latitude: lat,
      longitude: lng,
      address: addr,
    );
  }

  // Dismiss Emergency SOS Alert
  Future<void> dismissSos() async {
    await _dbService.clearFamilySos(currentFamilyName);
    _activeEmergencyAlert = null;
    _safeNotifyListeners();
  }

  // Switch Family Group
  Future<void> switchFamilyGroup(String newFamilyName) async {
    _currentFamilyName = newFamilyName;
    await PreferencesService.saveUserFamilyName(newFamilyName);

    try {
      final members = await _dbService.getFamilyMembers(newFamilyName);
      _familyMembers = _enrichWithContactNames(members);
      _subscribeToMembers(newFamilyName);
      _subscribeToEmergencyAlerts(newFamilyName);
      _subscribeToLocations(members);
    } catch (e) {
      debugPrint('[FamilyTracker] Switch group error: $e');
    }
    _safeNotifyListeners();
  }

  // Add Family Member
  Future<void> addMember(FamilyMemberModel member) async {
    try {
      await _dbService.addFamilyMember(member);
      await refresh(PreferencesService.getUserPhone() ?? '');
    } catch (e) {
      debugPrint('[FamilyTracker] Add member error: $e');
    }
  }

  // Delete Member
  Future<void> deleteMember(String memberId, String mobile) async {
    try {
      await _dbService.deleteFamilyMember(memberId, mobile);
      await refresh(PreferencesService.getUserPhone() ?? '');
    } catch (e) {
      debugPrint('[FamilyTracker] Delete member error: $e');
    }
  }

  // Refresh All
  Future<void> refresh(String userPhone) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      try {
        await ContactsService.syncDeviceContacts();
      } catch (_) {}
      if (userPhone.isNotEmpty) {
        await _locationService.updateAndPushLocation(userPhone);
      }
      final members = await _dbService.getFamilyMembers(_currentFamilyName);
      _familyMembers = _enrichWithContactNames(members);
      _subscribeToLocations(members);
      _subscribeToEmergencyAlerts(_currentFamilyName);
    } catch (e) {
      debugPrint('[FamilyTracker] Refresh error: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    _notifyDebounceTimer?.cancel();
    _locationService.stopContinuousTracking();
    _membersSubscription?.cancel();
    _emergencySubscription?.cancel();
    for (var sub in _locationSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
