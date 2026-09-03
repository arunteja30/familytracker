import 'dart:async';
import 'package:flutter/material.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
import '../services/location_service.dart';
import '../services/native_service.dart';

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

  // Initialize and Load Data
  Future<void> init(String userPhone) async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('[FamilyTracker] Initializing FamilyProvider for: $userPhone');

      // 1. Fetch all groups on Firebase that this phone is added to
      _userFamilyGroups = await _dbService.getFamilyNamesForPhone(userPhone);
      debugPrint('[FamilyTracker] Detected groups for user: $_userFamilyGroups');

      // 2. Determine best family group to load
      String? savedFamily = PreferencesService.getUserFamilyName();

      if (_userFamilyGroups.isNotEmpty) {
        // If saved group is in the user's groups, use it, otherwise use the first discovered group
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

      // 3. Fetch initial snapshot directly
      final initialMembers = await _dbService.getFamilyMembers(_currentFamilyName);
      _familyMembers = initialMembers;
      debugPrint('[FamilyTracker] Initial snapshot loaded: ${_familyMembers.length} members');

      // 4. Subscribe to real-time updates for the active family group
      _subscribeToMembers(_currentFamilyName);

      // 5. Start continuous background location tracking with foreground notification
      _locationService.startContinuousBackgroundLocationTracking(userPhone);
      await NativeService.startNativeStickyService();
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[FamilyTracker] Init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Subscribe to Live Members
  void _subscribeToMembers(String familyName) {
    _membersSubscription?.cancel();
    _membersSubscription =
        _dbService.streamFamilyMembers(familyName).listen((members) {
      _familyMembers = members;
      _subscribeToLocations(members);
      notifyListeners();
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
            notifyListeners();
          }
        });
      }
    }
  }

  // Switch Family Group
  Future<void> switchFamilyGroup(String newFamilyName) async {
    _currentFamilyName = newFamilyName;
    await PreferencesService.saveUserFamilyName(newFamilyName);
    
    // Fetch immediately then subscribe
    final members = await _dbService.getFamilyMembers(newFamilyName);
    _familyMembers = members;
    _subscribeToMembers(newFamilyName);
    _subscribeToLocations(members);
    notifyListeners();
  }

  // Add Family Member
  Future<void> addMember(FamilyMemberModel member) async {
    await _dbService.addFamilyMember(member);
    await refresh(PreferencesService.getUserPhone() ?? '');
  }

  // Delete Member
  Future<void> deleteMember(String memberId, String mobile) async {
    await _dbService.deleteFamilyMember(memberId, mobile);
    await refresh(PreferencesService.getUserPhone() ?? '');
  }

  // Refresh All
  Future<void> refresh(String userPhone) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (userPhone.isNotEmpty) {
        await _locationService.updateAndPushLocation(userPhone);
      }
      final members = await _dbService.getFamilyMembers(_currentFamilyName);
      _familyMembers = members;
      _subscribeToLocations(members);
    } catch (e) {
      debugPrint('[FamilyTracker] Refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
