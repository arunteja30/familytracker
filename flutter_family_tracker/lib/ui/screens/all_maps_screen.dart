import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  final List<Color> _markerColors = [
    const Color(0xFF4F46E5), // Indigo
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEC4899), // Pink
    const Color(0xFF8B5CF6), // Purple
  ];

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
  }

  @override
  void dispose() {
    for (var sub in _locationSubscriptions) {
      sub.cancel();
    }
    _placesSubscription?.cancel();
    super.dispose();
  }

  // Subscribe to real-time safe places for this family group
  void _subscribeToPlaces() {
    _placesSubscription = _dbService.streamFamilyPlaces(widget.familyName).listen((places) {
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
          fillColor: color.withValues(alpha: 0.18),
          strokeColor: color.withValues(alpha: 0.85),
          strokeWidth: 2,
        ),
      );

      // 2. Place Marker
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
                        : BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(
            title: '${place.category.displayName}: ${place.name}',
            snippet: '${place.isForAllMembers ? "For: All Family" : "For: ${place.targetMemberName}"} • Radius ${place.radiusMeters.round()}m',
          ),
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

  Future<Marker?> _buildMarkerForMember(
      FamilyMemberModel member, LocationDetailsModel? loc, int index) async {
    if (loc == null || (loc.latitude == 0.0 && loc.longitude == 0.0)) return null;

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
    if (loc.address.isEmpty || loc.address.startsWith('Lat:')) {
      GeocodingService.getAddressFromCoordinates(loc.latitude, loc.longitude)
          .then((addr) {
        if (mounted) {
          setState(() => _resolvedAddresses[member.mobile] = addr);
        }
      });
    } else {
      _resolvedAddresses[member.mobile] = loc.address;
    }

    final customIcon = await MarkerGenerator.createCustomMemberMarker(
      name: member.name,
      pinColor: color,
      localPhotoPath: photoFile?.path,
    );

    final lastUpdated = loc.timeStamp > 0
        ? DateFormat('MMM dd, yyyy • hh:mm:ss a').format(
            DateTime.fromMillisecondsSinceEpoch(loc.timeStamp),
          )
        : (loc.date.isNotEmpty ? loc.date : 'Recently');

    final displayAddr = _resolvedAddresses[member.mobile] ?? loc.address;

    return Marker(
      markerId: MarkerId(member.mobile),
      position: LatLng(loc.latitude, loc.longitude),
      icon: customIcon,
      infoWindow: InfoWindow(
        title: member.name,
        snippet: '🕒 $lastUpdated\n📍 $displayAddr\n⚡ Battery: ${loc.batteryPercentage}%',
      ),
      onTap: () {
        _focusMember(member);
      },
    );
  }

  Future<void> _updateMemberMarker(
      FamilyMemberModel member, LocationDetailsModel loc, int index) async {
    final marker = await _buildMarkerForMember(member, loc, index);
    if (marker != null && mounted) {
      setState(() {
        // Track live movement path for current active session
        final memberTrail =
            _sessionMovements.putIfAbsent(member.mobile, () => []);
        final newPoint = LatLng(loc.latitude, loc.longitude);
        if (memberTrail.isEmpty ||
            memberTrail.last.latitude != newPoint.latitude ||
            memberTrail.last.longitude != newPoint.longitude) {
          // If there was a previous location, create an intermediate update marker at that previous location
          if (memberTrail.isNotEmpty) {
            final stepIndex = memberTrail.length;
            final prevPoint = memberTrail.last;
            final nowStr = DateFormat('MMM dd, yyyy • hh:mm:ss a').format(DateTime.now());
            _markers.add(
              Marker(
                markerId: MarkerId('step_${member.mobile}_$stepIndex'),
                position: prevPoint,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                zIndexInt: 5,
                infoWindow: InfoWindow(
                  title: '${member.name} • Update #$stepIndex',
                  snippet: '🕒 $nowStr\n📍 Update Position',
                ),
              ),
            );
          }

          memberTrail.add(newPoint);
          if (memberTrail.length > 25) {
            memberTrail.removeAt(0);
          }
        }

        // Update current member marker
        _markers.removeWhere((m) => m.markerId.value == member.mobile);
        _markers.add(marker);

        _updateActiveMovementPolylines();
      });
    }
  }

  void _updateActiveMovementPolylines() {
    _polylines.clear();
    _adaptivePolylines.clear();

    for (int i = 0; i < widget.members.length; i++) {
      final member = widget.members[i];
      final trail = _sessionMovements[member.mobile];
      if (trail != null && trail.length >= 2) {
        // Show current movement trail only for active movements
        if (_selectedMember == null || _selectedMember!.mobile == member.mobile) {
          final color = _markerColors[i % _markerColors.length];
          _polylines.add(
            Polyline(
              polylineId: PolylineId('active_move_${member.mobile}'),
              points: List.from(trail),
              color: color,
              width: 4,
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
              strokeWidth: 4.0,
            ),
          );
        }
      }
    }
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

  Future<void> _focusMember(FamilyMemberModel member) async {
    setState(() {
      _selectedMember = member;
      _showBottomCard = true;
      _updateActiveMovementPolylines();
    });

    final loc = _liveLocations[member.mobile] ?? widget.locations[member.mobile];
    if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
      try {
        final GoogleMapController controller = await _controller.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(loc.latitude, loc.longitude),
              zoom: 16,
            ),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _fitAllBounds() async {
    setState(() {
      _selectedMember = null;
      _showBottomCard = false;
      _updateActiveMovementPolylines();
    });

    if (_markers.isEmpty) return;
    try {
      final GoogleMapController controller = await _controller.future;

      if (_markers.length == 1) {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _markers.first.position,
              zoom: 15,
            ),
          ),
        );
        return;
      }

      double minLat = _markers.first.position.latitude;
      double maxLat = _markers.first.position.latitude;
      double minLng = _markers.first.position.longitude;
      double maxLng = _markers.first.position.longitude;

      for (var marker in _markers) {
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

  @override
  Widget build(BuildContext context) {
    LatLng initialPos = const LatLng(17.3850, 78.4867);
    if (_markers.isNotEmpty) {
      initialPos = _markers.first.position;
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${FamilyProvider.formatFamilyDisplayName(widget.familyName)} Live Map'),
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
            tooltip: 'Safe Places & Geofencing',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () {
              final userPhone = PreferencesService.getUserPhone() ?? '';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlacesManagerScreen(
                    familyName: widget.familyName,
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
            points: widget.members.map((m) {
              final loc = _liveLocations[m.mobile] ?? widget.locations[m.mobile];
              return AdaptiveMapPoint(
                id: m.mobile,
                latitude: loc?.latitude ?? 0.0,
                longitude: loc?.longitude ?? 0.0,
                title: m.name,
                snippet: loc?.address ?? '',
                pinColor: MarkerGenerator.getMarkerColor(m.relationship),
                onTap: () {
                  _focusMember(m);
                },
              );
            }).where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList(),
            googleMarkers: {..._markers, ..._placeMarkers},
            googlePolylines: _polylines,
            googleCircles: _geofenceCircles,
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
                                    if (_selectedMember!.relationship.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _selectedMember!.relationship,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
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
