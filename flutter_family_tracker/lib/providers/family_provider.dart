import 'dart:async';
import 'package:flutter/material.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
import '../services/location_service.dart';
import '../services/native_service.dart';
import '../services/contacts_service.dart';

class FamilyProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locationService = LocationService();

  String _currentFamilyName = '';
  List<String> _userFamilyGroups = [];
  List<FamilyMemberModel> _familyMembers = [];
  final Map<String, LocationDetailsModel> _memberLocations = {};
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _membersSubscription;
  final Map<String, StreamSubscription> _locationSubscriptions = {};

  String get currentFamilyName =>
      _currentFamilyName.isNotEmpty ? _currentFamilyName : 'MyFamily';
  List<String> get userFamilyGroups => _userFamilyGroups;
  List<FamilyMemberModel> get familyMembers => _familyMembers;
  Map<String, LocationDetailsModel> get memberLocations => _memberLocations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _safeNotifyListeners() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
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
            _safeNotifyListeners();
          }
        }, onError: (err) {
          debugPrint('[FamilyTracker] Stream location error for ${member.mobile}: $err');
        });
      }
    }
  }

  // Switch Family Group
  Future<void> switchFamilyGroup(String newFamilyName) async {
    _currentFamilyName = newFamilyName;
    await PreferencesService.saveUserFamilyName(newFamilyName);

    try {
      final members = await _dbService.getFamilyMembers(newFamilyName);
      _familyMembers = _enrichWithContactNames(members);
      _subscribeToMembers(newFamilyName);
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
    } catch (e) {
      debugPrint('[FamilyTracker] Refresh error: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    _locationService.stopContinuousTracking();
    _membersSubscription?.cancel();
    for (var sub in _locationSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
