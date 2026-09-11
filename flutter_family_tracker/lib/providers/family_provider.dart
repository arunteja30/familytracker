import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/family_member_model.dart';
import '../models/location_details_model.dart';
import '../models/chat_message_model.dart';
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
  List<ChatMessageModel> _chatMessages = [];
  int _unreadChatCount = 0;
  final Set<String> _unreadMemberPhones = {};
  bool _isChatScreenActive = false;
  final Set<String> _processedChatMessageIds = {};
  bool _hasInitialChatLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _membersSubscription;
  StreamSubscription? _emergencySubscription;
  StreamSubscription? _chatSubscription;
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
  List<ChatMessageModel> get chatMessages => _chatMessages;
  int get unreadChatCount => _unreadChatCount;
  bool get hasUnreadChat => _unreadChatCount > 0;
  bool get isChatScreenActive => _isChatScreenActive;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool hasUnreadForMember(String? phone) {
    if (phone == null || phone.isEmpty) return false;
    final normalized = PhoneUtils.normalize(phone);
    return _unreadMemberPhones.contains(normalized);
  }

  void markChatReadForMember(String? phone) {
    if (phone != null && phone.isNotEmpty) {
      final normalized = PhoneUtils.normalize(phone);
      if (_unreadMemberPhones.remove(normalized)) {
        _safeNotifyListeners();
      }
    }
  }

  void markAllChatRead() {
    _unreadChatCount = 0;
    _unreadMemberPhones.clear();
    _safeNotifyListeners();
  }

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
      _subscribeToChat(_currentFamilyName);

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
        final senderName = alert['senderName']?.toString() ?? 'Family Member';
        final address = alert['address']?.toString() ?? '';
        final formattedPhone = PhoneUtils.formatDisplay(senderPhone);

        // Update persistent sticky notification for all family members
        NativeService.updateStickyNotification(
          title: '🚨 SOS: $senderName ($formattedPhone)',
          text: address.isNotEmpty
              ? '📍 $address • Tap to open live emergency map'
              : 'Emergency SOS distress active in $displayFamilyName',
          isSosActive: true,
        );

        // Fire heads-up sound & notification if sender is someone else
        if (!PhoneUtils.isSame(senderPhone, myPhone)) {
          NotificationService.showSosAlert(
            senderName: senderName,
            senderPhone: formattedPhone,
            address: address,
            familyName: displayFamilyName,
          );
        }
      } else {
        // Revert sticky notification back to standard family tracking
        NativeService.updateStickyNotification(
          title: 'FamilyTracker Active',
          text: 'Live family safety tracking active',
          isSosActive: false,
        );
        NotificationService.cancelSosAlert();
      }
      _safeNotifyListeners();
    }, onError: (err) {
      debugPrint('[FamilyTracker] Emergency stream error: $err');
    });
  }

  // Subscribe to Peer-to-Peer Family Group Chat
  void _subscribeToChat(String familyName) {
    _chatSubscription?.cancel();
    if (familyName.isEmpty) return;

    _chatSubscription =
        _dbService.streamChatMessages(familyName).listen((messages) {
      final myPhone = PreferencesService.getUserPhone() ?? '';

      // Process newly arrived / sent family messages
      if (messages.isNotEmpty) {
        if (_hasInitialChatLoaded) {
          for (final msg in messages) {
            if (!_processedChatMessageIds.contains(msg.messageId)) {
              _processedChatMessageIds.add(msg.messageId);

              // Notify if message was sent by another family member and user isn't currently viewing chat
              if (!PhoneUtils.isSame(msg.senderPhone, myPhone) &&
                  !_isChatScreenActive) {
                _unreadChatCount++;
                final normalizedSender = PhoneUtils.normalize(msg.senderPhone);
                if (normalizedSender.isNotEmpty) {
                  _unreadMemberPhones.add(normalizedSender);
                }
                NotificationService.showChatMessageNotification(
                  senderName: msg.senderName,
                  text: msg.isLocation
                      ? '📍 Shared live location pin'
                      : msg.text,
                  familyName: formatFamilyDisplayName(familyName),
                  notificationId: msg.messageId.hashCode,
                );
              }
            }
          }
        } else {
          // Initial snapshot load: mark all existing messages as processed
          for (final msg in messages) {
            _processedChatMessageIds.add(msg.messageId);
          }
          _hasInitialChatLoaded = true;
        }
      }

      _chatMessages = messages;
      _safeNotifyListeners();
    }, onError: (err) {
      debugPrint('[FamilyTracker] Chat stream error: $err');
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

  // Resolve current user's display name accurately from memory, contacts, and preferences
  String resolveCurrentUserName([String? candidateName]) {
    if (candidateName != null &&
        candidateName.trim().isNotEmpty &&
        candidateName.trim() != 'Family Member') {
      return candidateName.trim();
    }

    final prefName = PreferencesService.getUserName();
    if (prefName != null &&
        prefName.trim().isNotEmpty &&
        prefName.trim() != 'Family Member') {
      return prefName.trim();
    }

    final myPhone = PreferencesService.getUserPhone() ?? '';
    if (myPhone.isNotEmpty) {
      for (final m in _familyMembers) {
        if (DatabaseService.matchPhones(m.mobile, myPhone) &&
            m.name.trim().isNotEmpty &&
            m.name.trim() != 'Family Member') {
          PreferencesService.saveUserName(m.name.trim());
          return m.name.trim();
        }
      }

      final contactName = ContactsService.getContactName(myPhone);
      if (contactName.isNotEmpty && contactName != myPhone) {
        PreferencesService.saveUserName(contactName);
        return contactName;
      }
    }

    return 'Family Member';
  }

  // Resolve current location coordinates & address with multi-tier hardware GPS, cache & IP fallback
  Future<Map<String, dynamic>> resolveCurrentLocationAndAddress({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    double lat = latitude ?? 0.0;
    double lng = longitude ?? 0.0;
    String addr = address ?? '';

    final myPhone = PreferencesService.getUserPhone() ?? '';
    final normalizedPhone = PhoneUtils.normalize(myPhone);

    if (lat == 0.0 && lng == 0.0) {
      // 1. Try fast hardware GPS & IP fallback via LocationService
      try {
        final locDetails = await _locationService.getCurrentLocationDetails();
        if (locDetails != null && (locDetails.latitude != 0.0 || locDetails.longitude != 0.0)) {
          lat = locDetails.latitude;
          lng = locDetails.longitude;
          if (addr.isEmpty && locDetails.address.isNotEmpty) {
            addr = locDetails.address;
          }
        }
      } catch (e) {
        debugPrint('[FamilyTracker] LocationService resolution error: $e');
      }

      // 2. Check cached in-memory locations
      if (lat == 0.0 && lng == 0.0) {
        final cached = _memberLocations[normalizedPhone] ?? _memberLocations[myPhone];
        if (cached != null && (cached.latitude != 0.0 || cached.longitude != 0.0)) {
          lat = cached.latitude;
          lng = cached.longitude;
          if (addr.isEmpty && cached.address.isNotEmpty) {
            addr = cached.address;
          }
        }
      }

      // 3. Check Geolocator lastKnown
      if (lat == 0.0 && lng == 0.0) {
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null && (lastPos.latitude != 0.0 || lastPos.longitude != 0.0)) {
            lat = lastPos.latitude;
            lng = lastPos.longitude;
          }
        } catch (_) {}
      }
    }

    // Resolve human-readable address if missing or placeholder
    if ((lat != 0.0 || lng != 0.0) && (addr.isEmpty || addr.startsWith('Lat:'))) {
      try {
        final resolved = await GeocodingService.getAddressFromCoordinates(lat, lng);
        if (resolved.isNotEmpty && !resolved.startsWith('Lat:')) {
          addr = resolved;
        }
      } catch (_) {}

      if (addr.isEmpty || addr.startsWith('Lat:')) {
        addr = 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
      }
    }

    return {
      'latitude': lat,
      'longitude': lng,
      'address': addr,
    };
  }

  // Broadcast SOS Distress Event to all Family Devices
  Future<void> triggerSos({
    double? latitude,
    double? longitude,
    String? address,
    String? senderName,
  }) async {
    final myPhone = PreferencesService.getUserPhone() ?? '';
    final normalizedPhone = PhoneUtils.normalize(myPhone);
    final myName = resolveCurrentUserName(senderName);

    final loc = await resolveCurrentLocationAndAddress(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );

    final double lat = loc['latitude'] ?? 0.0;
    final double lng = loc['longitude'] ?? 0.0;
    final String addr = loc['address'] ?? '';

    debugPrint('[FamilyTracker] 🚨 Triggering SOS: sender=$myName ($normalizedPhone), lat=$lat, lng=$lng, addr=$addr, family=$currentFamilyName');

    // 1. Broadcast to emergency_alerts node in Firebase RTDB
    await _dbService.triggerFamilySos(
      familyName: currentFamilyName,
      senderPhone: normalizedPhone.isNotEmpty ? normalizedPhone : myPhone,
      senderName: myName,
      latitude: lat,
      longitude: lng,
      address: addr,
    );

    // 2. Save location to database if valid coordinates found
    if (lat != 0.0 || lng != 0.0) {
      try {
        final now = DateTime.now();
        final locationModel = LocationDetailsModel(
          latitude: lat,
          longitude: lng,
          timeStamp: now.millisecondsSinceEpoch,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          batteryPercentage: 100,
          address: addr,
          gpsStatus: 'SOS Distress Active',
        );
        await _dbService.saveLocation(normalizedPhone.isNotEmpty ? normalizedPhone : myPhone, locationModel);
      } catch (e) {
        debugPrint('[FamilyTracker] SOS saveLocation error: $e');
      }
    }

    // 3. Post SOS distress message into Family Group Chat
    try {
      final sosChatMessage = ChatMessageModel(
        messageId: '',
        senderPhone: normalizedPhone.isNotEmpty ? normalizedPhone : myPhone,
        senderName: myName,
        text: '🚨 EMERGENCY SOS: I need immediate help!\n$addr',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: 'LOCATION',
        latitude: lat,
        longitude: lng,
        address: addr,
      );
      await _dbService.sendChatMessage(currentFamilyName, sosChatMessage);
    } catch (e) {
      debugPrint('[FamilyTracker] SOS sendChatMessage error: $e');
    }

    // 4. Update notification on sender device with SOS Emergency Text
    try {
      await NotificationService.showSosBroadcastActiveNotification(
        familyName: displayFamilyName,
        address: addr,
      );
      await NativeService.updateStickyNotification(
        title: '🚨 SOS BROADCAST ACTIVE ($displayFamilyName)',
        text: addr.isNotEmpty
            ? '📍 $addr • Broadcasting distress to family'
            : 'Broadcasting distress alert to family circle',
        isSosActive: true,
      );
    } catch (e) {
      debugPrint('[FamilyTracker] SOS sender notification error: $e');
    }
  }

  // Dismiss Emergency SOS Alert
  Future<void> dismissSos() async {
    await _dbService.clearFamilySos(currentFamilyName);
    _activeEmergencyAlert = null;
    await NotificationService.cancelSosAlert();
    await NativeService.updateStickyNotification(
      title: 'FamilyTracker Active',
      text: 'Live family safety tracking active',
      isSosActive: false,
    );
    _safeNotifyListeners();
  }

  // Switch Family Group
  Future<void> switchFamilyGroup(String newFamilyName) async {
    _currentFamilyName = newFamilyName;
    _unreadChatCount = 0;
    _unreadMemberPhones.clear();
    _processedChatMessageIds.clear();
    _hasInitialChatLoaded = false;
    await PreferencesService.saveUserFamilyName(newFamilyName);

    try {
      final members = await _dbService.getFamilyMembers(newFamilyName);
      _familyMembers = _enrichWithContactNames(members);
      _subscribeToMembers(newFamilyName);
      _subscribeToEmergencyAlerts(newFamilyName);
      _subscribeToChat(newFamilyName);
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

  // Send Chat Text Message
  Future<void> sendChatMessage(String text) async {
    if (text.trim().isEmpty) return;
    final myPhone = PreferencesService.getUserPhone() ?? '';
    final myName = resolveCurrentUserName();

    final message = ChatMessageModel(
      messageId: '',
      senderPhone: PhoneUtils.normalize(myPhone),
      senderName: myName,
      text: text.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: 'TEXT',
    );

    await _dbService.sendChatMessage(currentFamilyName, message);
  }

  // Send Interactive Location Share in Chat
  Future<void> shareCurrentLocationInChat({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final myPhone = PreferencesService.getUserPhone() ?? '';
    final myName = resolveCurrentUserName();

    final loc = await resolveCurrentLocationAndAddress(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );

    final double lat = loc['latitude'] ?? 0.0;
    final double lng = loc['longitude'] ?? 0.0;
    final String addr = loc['address'] ?? '';

    final message = ChatMessageModel(
      messageId: '',
      senderPhone: PhoneUtils.normalize(myPhone),
      senderName: myName,
      text: '📍 Shared Location',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: 'LOCATION',
      latitude: lat,
      longitude: lng,
      address: addr,
    );

    await _dbService.sendChatMessage(currentFamilyName, message);
  }

  // Edit a Chat Message
  Future<void> editChatMessage(String messageId, String newText) async {
    await _dbService.editChatMessage(currentFamilyName, messageId, newText);
  }

  // Delete a Chat Message
  Future<void> deleteMessage(String messageId) async {
    await _dbService.deleteChatMessage(currentFamilyName, messageId);
  }

  // Delete Multiple Chat Messages in batch
  Future<void> deleteChatMessages(List<String> messageIds) async {
    await _dbService.deleteChatMessages(currentFamilyName, messageIds);
  }

  // Set whether user is actively viewing chat screen
  void setChatScreenActive(bool active) {
    _isChatScreenActive = active;
    if (active) {
      _unreadChatCount = 0;
      _unreadMemberPhones.clear();
    }
    _safeNotifyListeners();
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
      _subscribeToChat(_currentFamilyName);
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
    _chatSubscription?.cancel();
    for (var sub in _locationSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
