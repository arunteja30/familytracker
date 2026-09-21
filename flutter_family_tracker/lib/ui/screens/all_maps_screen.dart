import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../models/geofence_place_model.dart';
import '../../providers/family_provider.dart';
import '../../services/database_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/geofence_service.dart';
import '../../services/preferences_service.dart';
import '../../services/profile_image_service.dart';
import '../../utils/marker_generator.dart';
import '../../utils/proximity_utils.dart';
import '../widgets/adaptive_map_view.dart';
import '../widgets/buzzing_dot.dart';
import 'location_history_screen.dart';
import 'family_chat_screen.dart';
import 'places_manager_screen.dart';

class AllMapsScreen extends StatefulWidget {
  final String familyName;
  final List<FamilyMemberModel> members;
  final Map<String, LocationDetailsModel> locations;

  const AllMapsScreen({
    super.key,
    required this.familyName,
    required this.members,
    required this.locations,
  });

  @override
  State<AllMapsScreen> createState() => _AllMapsScreenState();
}

class _AllMapsScreenState extends State<AllMapsScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final fmap.MapController _flutterMapController = fmap.MapController();
  final DatabaseService _dbService = DatabaseService();
  final List<StreamSubscription> _locationSubscriptions = [];
  StreamSubscription? _placesSubscription;
  List<GeofencePlaceModel> _familyPlaces = [];
  final Set<Circle> _geofenceCircles = {};
  final Set<Marker> _placeMarkers = {};
  MapType _currentMapType = MapType.normal;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<AdaptivePolyline> _adaptivePolylines = [];
  final Map<String, List<LatLng>> _sessionMovements = {};
  final Map<String, LocationDetailsModel> _liveLocations = {};
  FamilyMemberModel? _selectedMember;
  final Map<String, String> _resolvedAddresses = {};
  final Map<String, File?> _memberPhotos = {};
  final Set<String> _checkedPhotos = {};
  bool _isCardExpanded = false;
  bool _showBottomCard = true;
  bool _showPlacesLayer = true;

  final List<Color> _markerColors = [
    const Color(0xFF4F46E5), // Indigo
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEC4899), // Pink
    const Color(0xFF8B5CF6), // Purple
  ];

  final Map<String, DateTime> _recentlyUpdatedMobiles = {};
  final Map<String, Timer> _pulseResetTimers = {};
  final Set<Circle> _pulseCircles = {};
  Timer? _radarPulseTimer;
  double _pulsePhase = 0.0;

  bool _hasAnyMovingMember() {
    for (final loc in _liveLocations.values) {
      if (loc.isMoving) return true;
    }
    return false;
  }

  String _formatRelativeTime(int timestampMs) {
    if (timestampMs <= 0) return 'Recently';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void initState() {
    super.initState();
    _liveLocations.addAll(widget.locations);
    if (widget.members.isNotEmpty) {
      _selectedMember = widget.members.first;
    }
    _loadPhotosAndBuildMarkers();
    _subscribeToLiveMovements();
    _subscribeToPlaces();

    // Continuous pulsing radar animation timer for Google Maps on mobile only
    if (!kIsWeb) {
      _radarPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (!mounted) return;
        if (_recentlyUpdatedMobiles.isNotEmpty || _hasAnyMovingMember()) {
          setState(() {
            _pulsePhase = _pulsePhase == 0.0 ? 1.0 : 0.0;
            _buildPulseCircles();
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant AllMapsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldRebuild = false;

    if (widget.familyName != oldWidget.familyName) {
      _subscribeToPlaces();
    }

    if (widget.members.length != oldWidget.members.length ||
        widget.locations.length != oldWidget.locations.length ||
        widget.familyName != oldWidget.familyName ||
        (_markers.isEmpty && widget.members.isNotEmpty)) {
      shouldRebuild = true;
    } else {
      for (final entry in widget.locations.entries) {
        final oldLoc = oldWidget.locations[entry.key];
        if (oldLoc == null ||
            oldLoc.latitude != entry.value.latitude ||
            oldLoc.longitude != entry.value.longitude) {
          shouldRebuild = true;
          break;
        }
      }
    }

    if (shouldRebuild) {
      _liveLocations.addAll(widget.locations);
      if (_selectedMember == null && widget.members.isNotEmpty) {
        _selectedMember = widget.members.first;
      }
      _subscribeToLiveMovements();
      _loadPhotosAndBuildMarkers();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_familyPlaces.isEmpty) {
      try {
        final fp = context.read<FamilyProvider>();
        if (fp.familyPlaces.isNotEmpty) {
          setState(() {
            _familyPlaces = fp.familyPlaces;
            _buildGeofenceOverlays();
          });
        }
        if (widget.familyName.trim().isEmpty && fp.currentFamilyName.trim().isNotEmpty) {
          _subscribeToPlaces();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _radarPulseTimer?.cancel();
    for (var timer in _pulseResetTimers.values) {
      timer.cancel();
    }
    for (var sub in _locationSubscriptions) {
      sub.cancel();
    }
    _placesSubscription?.cancel();
    super.dispose();
  }

  String _resolveFamilyName() {
    if (widget.familyName.trim().isNotEmpty) return widget.familyName.trim();
    final prefFamily = PreferencesService.getUserFamilyName();
    if (prefFamily != null && prefFamily.trim().isNotEmpty) return prefFamily.trim();
    try {
      final fp = context.read<FamilyProvider>();
      if (fp.currentFamilyName.trim().isNotEmpty) return fp.currentFamilyName.trim();
    } catch (_) {}
    return '';
  }

  // Subscribe to real-time safe places for this family group
  void _subscribeToPlaces() {
    _placesSubscription?.cancel();

    // Check if FamilyProvider already has cached places as an immediate seed
    try {
      final fp = context.read<FamilyProvider>();
      if (fp.familyPlaces.isNotEmpty && _familyPlaces.isEmpty) {
        _familyPlaces = fp.familyPlaces;
        _buildGeofenceOverlays();
      }
    } catch (_) {}

    final family = _resolveFamilyName();
    if (family.isEmpty) return;

    _placesSubscription = _dbService.streamFamilyPlaces(family).listen((places) {
      if (mounted) {
        setState(() {
          _familyPlaces = places;
          _buildGeofenceOverlays();
        });
      }
    });
  }

  void _buildGeofenceOverlays() {
    final Set<Circle> circles = {};
    final Set<Marker> placeMarkers = {};

    for (final place in _familyPlaces) {
      if (place.latitude == 0.0 && place.longitude == 0.0) continue;

      final color = place.category.color;
      final latLng = LatLng(place.latitude, place.longitude);

      // 1. Safe Zone Circle Overlay
      circles.add(
        Circle(
          circleId: CircleId('geofence_${place.id}'),
          center: latLng,
          radius: place.radiusMeters,
          fillColor: color.withValues(alpha: 0.22),
          strokeColor: color.withValues(alpha: 0.90),
          strokeWidth: 2,
        ),
      );

      // 2. Place Marker for Google Maps (Native)
      placeMarkers.add(
        Marker(
          markerId: MarkerId('place_${place.id}'),
          position: latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            place.category == PlaceCategory.home
                ? BitmapDescriptor.hueGreen
                : place.category == PlaceCategory.school
                    ? BitmapDescriptor.hueAzure
                    : place.category == PlaceCategory.work
                        ? BitmapDescriptor.hueOrange
                        : place.category == PlaceCategory.gym
                            ? BitmapDescriptor.hueRose
                            : BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(
            title: '${place.category.displayName}: ${place.name}',
            snippet: '${place.isForAllMembers ? "For: All Family" : "For: ${place.targetMemberName}"} • Radius ${place.radiusMeters.round()}m',
            onTap: () => _showPlaceDetailsSheet(place),
          ),
          onTap: () => _showPlaceDetailsSheet(place),
        ),
      );
    }

    _geofenceCircles.clear();
    _geofenceCircles.addAll(circles);
    _placeMarkers.clear();
    _placeMarkers.addAll(placeMarkers);
  }

  // Subscribe to live location stream for all family members to track movements live
  void _subscribeToLiveMovements() {
    for (var sub in _locationSubscriptions) {
      sub.cancel();
    }
    _locationSubscriptions.clear();

    for (int i = 0; i < widget.members.length; i++) {
      final member = widget.members[i];
      final memberIndex = i;

      final sub = _dbService.streamLocationDetails(member.mobile).listen((newLoc) {
        if (newLoc != null &&
            (newLoc.latitude != 0.0 || newLoc.longitude != 0.0) &&
            mounted) {
          final oldLoc = _liveLocations[member.mobile];
          final hasMoved = oldLoc == null ||
              (oldLoc.latitude - newLoc.latitude).abs() > 0.00001 ||
              (oldLoc.longitude - newLoc.longitude).abs() > 0.00001;

          _liveLocations[member.mobile] = newLoc;

          if (hasMoved) {
            _updateMemberMarker(member, newLoc, memberIndex);
          }

          // Real-time Geofence Safe Place Evaluation (Arrival / Departure)
          if (_familyPlaces.isNotEmpty) {
            GeofenceService().evaluateMemberLocation(
              member: member,
              location: newLoc,
              places: _familyPlaces,
            );
          }
        }
      });
      _locationSubscriptions.add(sub);
    }
  }

  LocationDetailsModel? _getMemberLocation(String mobile) {
    final direct = _liveLocations[mobile] ?? widget.locations[mobile];
    if (direct != null && (direct.latitude != 0.0 || direct.longitude != 0.0)) {
      return direct;
    }
    final normalized = DatabaseService.normalizePhone(mobile);
    for (final entry in _liveLocations.entries) {
      if (DatabaseService.normalizePhone(entry.key) == normalized) {
        return entry.value;
      }
    }
    for (final entry in widget.locations.entries) {
      if (DatabaseService.normalizePhone(entry.key) == normalized) {
        return entry.value;
      }
    }
    return null;
  }

  Future<Marker?> _buildMarkerForMember(
      FamilyMemberModel member, LocationDetailsModel? loc, int index) async {
    LocationDetailsModel? effectiveLoc = loc ?? _getMemberLocation(member.mobile);
    if (effectiveLoc == null || (effectiveLoc.latitude == 0.0 && effectiveLoc.longitude == 0.0)) {
      effectiveLoc = await _dbService.getLocationDetails(member.mobile);
      if (effectiveLoc != null && (effectiveLoc.latitude != 0.0 || effectiveLoc.longitude != 0.0)) {
        _liveLocations[member.mobile] = effectiveLoc;
      }
    }
    if (effectiveLoc == null || (effectiveLoc.latitude == 0.0 && effectiveLoc.longitude == 0.0)) return null;

    final color = _markerColors[index % _markerColors.length];
    File? photoFile;
    if (_checkedPhotos.contains(member.mobile)) {
      photoFile = _memberPhotos[member.mobile];
    } else {
      photoFile = await ProfileImageService.getProfileImageFile(member.mobile);
      _memberPhotos[member.mobile] = photoFile;
      _checkedPhotos.add(member.mobile);
    }

    // Resolve address in background if missing
    if (effectiveLoc.address.isEmpty || effectiveLoc.address.startsWith('Lat:')) {
      GeocodingService.getAddressFromCoordinates(effectiveLoc.latitude, effectiveLoc.longitude)
          .then((addr) {
        if (mounted) {
          setState(() => _resolvedAddresses[member.mobile] = addr);
        }
      });
    } else {
      _resolvedAddresses[member.mobile] = effectiveLoc.address;
    }

    final isSelected = _selectedMember != null && DatabaseService.matchPhones(_selectedMember!.mobile, member.mobile);
    final relativeTime = effectiveLoc.timeStamp > 0
        ? _formatRelativeTime(effectiveLoc.timeStamp)
        : (effectiveLoc.date.isNotEmpty ? effectiveLoc.date : 'Recently');
    final updatedTime = _recentlyUpdatedMobiles[member.mobile];
    final isRecentlyUpdated = updatedTime != null && DateTime.now().difference(updatedTime).inSeconds < 15;
    final isMoving = effectiveLoc.isMoving || isRecentlyUpdated;

    BitmapDescriptor customIcon;
    try {
      customIcon = await MarkerGenerator.createCustomMemberMarker(
        name: member.name,
        pinColor: isSelected ? const Color(0xFFF59E0B) : color,
        localPhotoPath: photoFile?.path,
        isHighlighted: isSelected,
        lastUpdated: relativeTime,
        batteryPercentage: effectiveLoc.batteryPercentage,
        isMoving: isMoving,
      );
    } catch (e) {
      debugPrint('[AllMapsScreen] Error creating custom marker: $e');
      customIcon = BitmapDescriptor.defaultMarkerWithHue(
        isSelected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
      );
    }

    final displayAddr = _resolvedAddresses[member.mobile] ?? effectiveLoc.address;

    return Marker(
      markerId: MarkerId(member.mobile),
      position: LatLng(effectiveLoc.latitude, effectiveLoc.longitude),
      icon: customIcon,
      zIndexInt: isSelected ? 999 : (10 + index),
      infoWindow: InfoWindow(
        title: isSelected ? '⭐ ${member.name} (Selected)' : member.name,
        snippet: '🕒 $relativeTime\n📍 $displayAddr\n⚡ Battery: ${effectiveLoc.batteryPercentage}%${effectiveLoc.isMoving ? " • 🚗 ${effectiveLoc.formattedSpeed}" : ""}',
      ),
      onTap: () {
        _focusMember(member);
      },
    );
  }

  Future<void> _updateMemberMarker(
      FamilyMemberModel member, LocationDetailsModel loc, int index) async {
    // Record recent movement/update timestamp to trigger blinking animation
    _recentlyUpdatedMobiles[member.mobile] = DateTime.now();
    _pulseResetTimers[member.mobile]?.cancel();
    _pulseResetTimers[member.mobile] = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _recentlyUpdatedMobiles.remove(member.mobile);
          _buildPulseCircles();
        });
      }
    });

    final marker = await _buildMarkerForMember(member, loc, index);
    if (marker != null && mounted) {
      setState(() {
        // Track live coordinates in memory for individual tracking
        final memberTrail =
            _sessionMovements.putIfAbsent(member.mobile, () => []);
        final newPoint = LatLng(loc.latitude, loc.longitude);
        if (memberTrail.isEmpty ||
            memberTrail.last.latitude != newPoint.latitude ||
            memberTrail.last.longitude != newPoint.longitude) {
          memberTrail.add(newPoint);
          if (memberTrail.length > 30) {
            memberTrail.removeAt(0);
          }
        }

        // Update current member marker position cleanly (no intermediate clutter markers)
        _markers.removeWhere((m) => m.markerId.value == member.mobile);
        _markers.add(marker);

        _updateActiveMovementPolylines();
        _buildPulseCircles();
      });
    }
  }

  void _updateActiveMovementPolylines() {
    _polylines.clear();
    _adaptivePolylines.clear();

    // User requirement: When ALL is selected (_selectedMember == null),
    // DO NOT draw polylines. Just update member positions and alert with animations!
    if (_selectedMember == null) {
      return;
    }

    final member = _selectedMember!;
    final trail = _sessionMovements[member.mobile];
    if (trail != null && trail.length >= 2) {
      final index = widget.members.indexWhere((m) => m.mobile == member.mobile);
      final color = _markerColors[(index >= 0 ? index : 0) % _markerColors.length];
      _polylines.add(
        Polyline(
          polylineId: PolylineId('active_move_${member.mobile}'),
          points: List.from(trail),
          color: color,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );

      _adaptivePolylines.add(
        AdaptivePolyline(
          id: 'active_move_${member.mobile}',
          points: trail.map((p) => ll.LatLng(p.latitude, p.longitude)).toList(),
          color: color,
          strokeWidth: 5.0,
        ),
      );
    }
  }

  void _buildPulseCircles() {
    final Set<Circle> circles = {};
    final now = DateTime.now();

    for (int i = 0; i < widget.members.length; i++) {
      final member = widget.members[i];
      final loc = _liveLocations[member.mobile] ?? widget.locations[member.mobile];
      if (loc == null || (loc.latitude == 0.0 && loc.longitude == 0.0)) continue;

      final updatedTime = _recentlyUpdatedMobiles[member.mobile];
      final isRecentlyUpdated = updatedTime != null && now.difference(updatedTime).inSeconds < 15;
      final isMoving = loc.isMoving;

      if (isMoving || isRecentlyUpdated) {
        final alertColor = isMoving ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
        final baseRadius = isMoving ? 55.0 : 38.0;
        final animatedRadius = baseRadius + (_pulsePhase * 20.0);
        final animatedAlpha = (0.28 - (_pulsePhase * 0.14)).clamp(0.08, 0.35);

        circles.add(
          Circle(
            circleId: CircleId('pulse_${member.mobile}'),
            center: LatLng(loc.latitude, loc.longitude),
            radius: animatedRadius,
            fillColor: alertColor.withValues(alpha: animatedAlpha),
            strokeColor: alertColor.withValues(alpha: 0.90),
            strokeWidth: 2,
          ),
        );
      }
    }

    _pulseCircles.clear();
    _pulseCircles.addAll(circles);
  }

  Future<void> _loadPhotosAndBuildMarkers() async {
    // Generate markers in parallel across all members using cached bitmaps
    final markerFutures = widget.members.asMap().entries.map((entry) async {
      final i = entry.key;
      final member = entry.value;
      final loc = _liveLocations[member.mobile] ?? widget.locations[member.mobile];
      return await _buildMarkerForMember(member, loc, i);
    });

    final resolvedMarkers = await Future.wait(markerFutures);

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(resolvedMarkers.whereType<Marker>());
      });
    }
  }

  Future<void> _updateSingleMemberMarker(FamilyMemberModel targetMember) async {
    final index = widget.members.indexWhere((m) => m.mobile == targetMember.mobile);
    if (index < 0) return;
    final loc = _getMemberLocation(targetMember.mobile);
    final marker = await _buildMarkerForMember(targetMember, loc, index);
    if (marker != null && mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == targetMember.mobile);
        _markers.add(marker);
      });
    }
  }

  Future<void> _focusMember(FamilyMemberModel member) async {
    final previousSelected = _selectedMember;
    setState(() {
      _selectedMember = member;
      _showBottomCard = true;
      _updateActiveMovementPolylines();
    });

    // Selectively update only the affected member markers (0ms instantaneous highlight)
    if (previousSelected != null && previousSelected.mobile != member.mobile) {
      _updateSingleMemberMarker(previousSelected);
    }
    _updateSingleMemberMarker(member);

    // Robust multi-tier location resolution
    LocationDetailsModel? loc = _getMemberLocation(member.mobile);
    if (loc == null || (loc.latitude == 0.0 && loc.longitude == 0.0)) {
      loc = await _dbService.getLocationDetails(member.mobile);
      if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
        _liveLocations[member.mobile] = loc;
      }
    }

    if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
      // 1. Zoom into the selected member on Web (zoom 17.0 for close marker focus)
      try {
        _flutterMapController.move(ll.LatLng(loc.latitude, loc.longitude), 17.0);
      } catch (_) {}

      // 2. Animate camera and zoom into selected member marker on Google Maps
      try {
        final GoogleMapController controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(loc.latitude, loc.longitude),
              zoom: 17.0,
            ),
          ),
        );
        await controller.showMarkerInfoWindow(MarkerId(member.mobile));
      } catch (_) {}
    }
  }

  Future<void> _fitAllBounds() async {
    final previousSelected = _selectedMember;
    setState(() {
      _selectedMember = null;
      _showBottomCard = false;
      _updateActiveMovementPolylines();
    });

    // Reset marker highlights back to normal selectively
    if (previousSelected != null) {
      _updateSingleMemberMarker(previousSelected);
    }

    final targetMarkers = _showPlacesLayer && _placeMarkers.isNotEmpty
        ? {..._markers, ..._placeMarkers}
        : _markers;

    if (targetMarkers.isEmpty) return;

    // Move Web FlutterMap camera to fit all members and safe places
    try {
      if (targetMarkers.length == 1) {
        _flutterMapController.move(
          ll.LatLng(targetMarkers.first.position.latitude, targetMarkers.first.position.longitude),
          14.0,
        );
      } else if (targetMarkers.length > 1) {
        double minLat = targetMarkers.first.position.latitude;
        double maxLat = targetMarkers.first.position.latitude;
        double minLng = targetMarkers.first.position.longitude;
        double maxLng = targetMarkers.first.position.longitude;

        for (var marker in targetMarkers) {
          if (marker.position.latitude < minLat) minLat = marker.position.latitude;
          if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
          if (marker.position.longitude < minLng) minLng = marker.position.longitude;
          if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
        }

        final centerLat = (minLat + maxLat) / 2;
        final centerLng = (minLng + maxLng) / 2;
        _flutterMapController.move(ll.LatLng(centerLat, centerLng), 13.0);
      }
    } catch (_) {}

    // Animate Google Maps camera to fit all members & safe places on Mobile
    try {
      final GoogleMapController controller = await _controller.future;

      if (targetMarkers.length == 1) {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: targetMarkers.first.position,
              zoom: 15,
            ),
          ),
        );
        return;
      }

      double minLat = targetMarkers.first.position.latitude;
      double maxLat = targetMarkers.first.position.latitude;
      double minLng = targetMarkers.first.position.longitude;
      double maxLng = targetMarkers.first.position.longitude;

      for (var marker in targetMarkers) {
        if (marker.position.latitude < minLat) minLat = marker.position.latitude;
        if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
        if (marker.position.longitude < minLng) minLng = marker.position.longitude;
        if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
      }

      controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    } catch (_) {}
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showPlaceDetailsSheet(GeofencePlaceModel place) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: place.category.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: place.category.color, width: 2),
                    ),
                    child: Icon(place.category.icon, color: place.category.color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: place.category.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                place.category.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: place.category.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Radius: ${place.radiusMeters.round()}m',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Details Grid
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Applicable To', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(height: 3),
                          Text(
                            place.isForAllMembers ? 'All Family Members' : place.targetMemberName,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Schedule Window', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(height: 3),
                          Text(
                            place.formattedSchedule,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Actions Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (kIsWeb) {
                          _flutterMapController.move(
                            ll.LatLng(place.latitude, place.longitude),
                            15.5,
                          );
                        } else {
                          _controller.future.then((c) {
                            c.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                LatLng(place.latitude, place.longitude),
                                15.5,
                              ),
                            );
                          });
                        }
                      },
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Center on Map'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final userPhone = PreferencesService.getUserPhone() ?? '';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlacesManagerScreen(
                              familyName: _resolveFamilyName(),
                              userPhone: userPhone,
                              initialLat: place.latitude,
                              initialLng: place.longitude,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                      label: const Text('Manage Places'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<AdaptiveMapPoint> _buildAdaptiveMapPoints() {
    final List<AdaptiveMapPoint> points = [];

    for (final m in widget.members) {
      final loc = _getMemberLocation(m.mobile);
      if (loc == null || (loc.latitude == 0.0 && loc.longitude == 0.0)) continue;

      final isSelected = _selectedMember != null && DatabaseService.matchPhones(_selectedMember!.mobile, m.mobile);
      final updatedTime = _recentlyUpdatedMobiles[m.mobile];
      final isRecentlyUpdated = updatedTime != null && DateTime.now().difference(updatedTime).inSeconds < 15;
      final isMoving = loc.isMoving;
      final relativeTime = loc.timeStamp > 0
          ? _formatRelativeTime(loc.timeStamp)
          : (loc.date.isNotEmpty ? loc.date : 'Recently');

      points.add(
        AdaptiveMapPoint(
          id: m.mobile,
          latitude: loc.latitude,
          longitude: loc.longitude,
          title: isSelected ? '⭐ ${m.name}' : m.name,
          snippet: loc.address,
          pinColor: isSelected ? const Color(0xFFF59E0B) : MarkerGenerator.getMarkerColor(m.relationship),
          isSelected: isSelected,
          isMoving: isMoving,
          isUpdating: isRecentlyUpdated,
          lastUpdated: relativeTime,
          batteryPercentage: loc.batteryPercentage,
          photoFile: _memberPhotos[m.mobile],
          localPhotoPath: _memberPhotos[m.mobile]?.path,
          onTap: () => _focusMember(m),
        ),
      );
    }

    // Safe Places Markers on Web (when Safe Places Layer is toggled on)
    if (_showPlacesLayer) {
      for (final place in _familyPlaces) {
        if (place.latitude == 0.0 && place.longitude == 0.0) continue;

        points.add(
          AdaptiveMapPoint(
            id: 'place_${place.id}',
            latitude: place.latitude,
            longitude: place.longitude,
            title: '${place.category.displayName}: ${place.name}',
            snippet: '${place.isForAllMembers ? "For: All Family" : "For: ${place.targetMemberName}"} • Radius ${place.radiusMeters.round()}m',
            pinColor: place.category.color,
            isPlace: true,
            placeIcon: place.category.icon,
            onTap: () => _showPlaceDetailsSheet(place),
          ),
        );
      }
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    LatLng initialPos = const LatLng(17.3850, 78.4867);
    if (_markers.isNotEmpty) {
      initialPos = _markers.first.position;
    } else if (_familyPlaces.isNotEmpty && _familyPlaces.first.latitude != 0.0) {
      initialPos = LatLng(_familyPlaces.first.latitude, _familyPlaces.first.longitude);
    }

    final selectedLoc = _selectedMember != null
        ? (_liveLocations[_selectedMember!.mobile] ??
            widget.locations[_selectedMember!.mobile])
        : null;

    final selectedPhoto = _selectedMember != null
        ? _memberPhotos[_selectedMember!.mobile]
        : null;

    final formattedTime = selectedLoc != null && selectedLoc.timeStamp > 0
        ? DateFormat('MMM dd, yyyy • hh:mm:ss a').format(
            DateTime.fromMillisecondsSinceEpoch(selectedLoc.timeStamp),
          )
        : (selectedLoc?.date.isNotEmpty == true
            ? selectedLoc!.date
            : 'Pending sync...');

    final currentAddress = _selectedMember != null
        ? (_resolvedAddresses[_selectedMember!.mobile] ??
            (selectedLoc?.address.isNotEmpty == true
                ? selectedLoc!.address
                : 'Fetching street address...'))
        : 'Select a member';

    final userPhone = PreferencesService.getUserPhone() ?? '';
    final isSelf = _selectedMember != null && DatabaseService.matchPhones(_selectedMember!.mobile, userPhone);
    LocationDetailsModel? currentUserLoc;
    if (!isSelf && userPhone.isNotEmpty) {
      currentUserLoc = _liveLocations[userPhone] ?? widget.locations[userPhone];
    }
    final relativeDistance = (!isSelf && currentUserLoc != null && selectedLoc != null)
        ? ProximityUtils.getRelativeDistance(
            userLat: currentUserLoc.latitude,
            userLng: currentUserLoc.longitude,
            targetLat: selectedLoc.latitude,
            targetLng: selectedLoc.longitude,
          )
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text('${FamilyProvider.formatFamilyDisplayName(_resolveFamilyName().isNotEmpty ? _resolveFamilyName() : widget.familyName)} Live Map'),
        actions: [
          PopupMenuButton<MapType>(
            icon: const Icon(Icons.layers_rounded),
            onSelected: (type) => setState(() => _currentMapType = type),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: MapType.normal,
                child: Text('Normal Map'),
              ),
              const PopupMenuItem(
                value: MapType.satellite,
                child: Text('Satellite Map'),
              ),
              const PopupMenuItem(
                value: MapType.terrain,
                child: Text('Terrain Map'),
              ),
              const PopupMenuItem(
                value: MapType.hybrid,
                child: Text('Hybrid Map'),
              ),
            ],
          ),
          IconButton(
            tooltip: _showPlacesLayer ? 'Hide Safe Zones' : 'Show Safe Zones',
            icon: Icon(
              _showPlacesLayer ? Icons.shield_rounded : Icons.shield_outlined,
              color: _showPlacesLayer ? const Color(0xFF10B981) : null,
            ),
            onPressed: () => setState(() => _showPlacesLayer = !_showPlacesLayer),
          ),
          IconButton(
            tooltip: 'Safe Places & Geofencing',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () {
              final userPhone = PreferencesService.getUserPhone() ?? '';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlacesManagerScreen(
                    familyName: _resolveFamilyName(),
                    userPhone: userPhone,
                    initialLat: _selectedMember != null
                        ? (_liveLocations[_selectedMember!.mobile]?.latitude ?? initialPos.latitude)
                        : initialPos.latitude,
                    initialLng: _selectedMember != null
                        ? (_liveLocations[_selectedMember!.mobile]?.longitude ?? initialPos.longitude)
                        : initialPos.longitude,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'View All Members',
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _fitAllBounds,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Google / Adaptive Map (Full Screen)
          AdaptiveMapView(
            initialLat: initialPos.latitude,
            initialLng: initialPos.longitude,
            initialZoom: 12,
            mapType: _currentMapType,
            flutterMapController: _flutterMapController,
            points: kIsWeb ? _buildAdaptiveMapPoints() : const [],
            googleMarkers: _showPlacesLayer
                ? {..._markers, ..._placeMarkers}
                : _markers,
            googlePolylines: _polylines,
            googleCircles: _showPlacesLayer
                ? {..._geofenceCircles, ..._pulseCircles}
                : _pulseCircles,
            polylines: _adaptivePolylines,
            onGoogleMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
              Future.delayed(const Duration(milliseconds: 600), _fitAllBounds);
            },
          ),

          // 2. Top Floating Member Selector Pill Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: RepaintBoundary(
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.cardBorder.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  children: [
                    // "All Members" Filter Pill
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: _fitAllBounds,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: _selectedMember == null
                                ? AppColors.primary
                                : AppColors.bgSurfaceElevated,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_alt_rounded,
                                size: 16,
                                color: _selectedMember == null
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'All (${widget.members.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedMember == null
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Individual Member Avatar Pills
                    for (int i = 0; i < widget.members.length; i++) ...[
                      _buildMemberChip(widget.members[i], i),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 3. Compact Bottom Floating Details Card
          if (_selectedMember != null && _showBottomCard)
            Positioned(
              left: 14,
              right: 14,
              bottom: 16,
              child: RepaintBoundary(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.cardBorder,
                      width: 1.2,
                    ),
                  ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Compact Row
                    InkWell(
                      onTap: () {
                        setState(() => _isCardExpanded = !_isCardExpanded);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        children: [
                          // Avatar with battery status ring
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
                                backgroundImage: selectedPhoto != null
                                    ? FileImage(selectedPhoto)
                                    : null,
                                child: selectedPhoto == null
                                    ? Text(
                                        _selectedMember!.name.isNotEmpty
                                            ? _selectedMember!.name[0].toUpperCase()
                                            : 'M',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      )
                                    : null,
                              ),
                              if (selectedLoc != null && selectedLoc.batteryPercentage > 0)
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: selectedLoc.batteryPercentage > 20
                                          ? AppColors.success
                                          : AppColors.danger,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Text(
                                      '${selectedLoc.batteryPercentage}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),

                          // Name, Coordinates & Address Summary
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _selectedMember!.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (Provider.of<FamilyProvider>(context, listen: false).isMemberAdmin(_selectedMember!)) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.admin_panel_settings_rounded, size: 11, color: Color(0xFFB45309)),
                                            SizedBox(width: 3),
                                            Text(
                                              'Admin',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFB45309),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (selectedLoc != null && selectedLoc.isMoving) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.directions_car_filled_rounded, size: 10, color: Color(0xFF0D9488)),
                                            const SizedBox(width: 3),
                                            Text(
                                              selectedLoc.formattedSpeed,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0D9488),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (relativeDistance.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.near_me_rounded, size: 10, color: AppColors.primary),
                                            const SizedBox(width: 3),
                                            Text(
                                              relativeDistance,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),

                                // 1. Lat & Lng Coordinates
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.gps_fixed_rounded,
                                      size: 12,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      selectedLoc != null && selectedLoc.latitude != 0.0
                                          ? 'Lat: ${selectedLoc.latitude.toStringAsFixed(6)}, Lng: ${selectedLoc.longitude.toStringAsFixed(6)}'
                                          : 'No GPS Fix',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),

                                // 2. Street Address below Lat and Lng
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.location_on_rounded,
                                      size: 13,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        currentAddress,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Quick Call Button
                          IconButton.filledTonal(
                            onPressed: () => _makeCall(_selectedMember!.mobile),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.successBg,
                              foregroundColor: AppColors.success,
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Expand / Collapse Toggle Arrow
                          Icon(
                            _isCardExpanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            color: AppColors.textMuted,
                            size: 22,
                          ),
                        ],
                      ),
                    ),

                    // Expanded Section
                    if (_isCardExpanded) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.cardBorder),
                      const SizedBox(height: 10),

                      // Last Updated Time
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            'Last updated: $formattedTime',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Full Action Buttons Row
                      Row(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (ctx) {
                                final hasUnread = _selectedMember != null &&
                                    ctx.watch<FamilyProvider>().hasUnreadForMember(_selectedMember!.mobile);
                                return OutlinedButton.icon(
                                  onPressed: () {
                                    if (_selectedMember != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FamilyChatScreen(
                                            targetMember: _selectedMember,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: BuzzingBadge(
                                    showBadge: hasUnread,
                                    dotSize: 7,
                                    top: -2,
                                    right: -2,
                                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                  ),
                                  label: const Text('Chat', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LocationHistoryScreen(
                                      member: _selectedMember!,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.history_rounded, size: 16),
                              label: const Text('History', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberChip(FamilyMemberModel member, int index) {
    final isSelected = _selectedMember?.mobile == member.mobile;
    final photo = _memberPhotos[member.mobile];
    final loc = _liveLocations[member.mobile] ?? widget.locations[member.mobile];
    final color = _markerColors[index % _markerColors.length];

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => _focusMember(member),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.bgSurfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.cardBorder,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              CircleAvatar(
                radius: 14,
                backgroundColor: isSelected ? Colors.white : color.withValues(alpha: 0.2),
                backgroundImage: photo != null ? FileImage(photo) : null,
                child: photo == null
                    ? Text(
                        member.name.isNotEmpty ? member.name[0].toUpperCase() : 'M',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.primary : color,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),

              // First Name
              Text(
                member.name.split(' ').first,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),

              // Battery Status
              if (loc != null && loc.batteryPercentage > 0) ...[
                const SizedBox(width: 5),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white
                        : (loc.batteryPercentage > 20
                            ? AppColors.success
                            : AppColors.danger),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
