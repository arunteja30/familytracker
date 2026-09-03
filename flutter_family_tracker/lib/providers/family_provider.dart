import 'dart:async';
import 'package:flutter/material.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
import '../services/location_service.dart';

class FamilyProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locationService = LocationService();

  String _currentFamilyName = 'MyFamily';
  List<FamilyMemberModel> _familyMembers = [];
  final Map<String, LocationDetailsModel> _memberLocations = {};
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _membersSubscription;
  final Map<String, StreamSubscription> _locationSubscriptions = {};

  String get currentFamilyName => _currentFamilyName;
  List<FamilyMemberModel> get familyMembers => _familyMembers;
  Map<String, LocationDetailsModel> get memberLocations => _memberLocations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Initialize and Load Data
  Future<void> init(String userPhone) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Check saved family name or fetch from DB
      String? familyName = PreferencesService.getUserFamilyName();
      if (familyName == null || familyName.isEmpty) {
        familyName = await _dbService.getFamilyNameFromMobile(userPhone);
        if (familyName != null && familyName.isNotEmpty) {
          await PreferencesService.saveUserFamilyName(familyName);
        } else {
          familyName = 'MyFamily';
          await PreferencesService.saveUserFamilyName(familyName);
        }
      }

      _currentFamilyName = familyName;
      _subscribeToMembers(_currentFamilyName);

      // Trigger location update for self
      await _locationService.updateAndPushLocation(userPhone);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Subscribe to Live Members
  void _subscribeToMembers(String familyName) {
    _membersSubscription?.cancel();
    _membersSubscription = _dbService.streamFamilyMembers(familyName).listen((members) {
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
    _subscribeToMembers(newFamilyName);
    notifyListeners();
  }

  // Add Family Member
  Future<void> addMember(FamilyMemberModel member) async {
    await _dbService.addFamilyMember(_currentFamilyName, member);
    notifyListeners();
  }

  // Delete Member
  Future<void> deleteMember(String mobile) async {
    await _dbService.deleteFamilyMember(_currentFamilyName, mobile);
    notifyListeners();
  }

  // Refresh All
  Future<void> refresh(String userPhone) async {
    await _locationService.updateAndPushLocation(userPhone);
    final members = await _dbService.getFamilyMembers(_currentFamilyName);
    _familyMembers = members;
    notifyListeners();
  }

  @override
  void dispose() {
    _membersSubscription?.cancel();
    for (var sub in _locationSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
