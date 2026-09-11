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
import '../../providers/family_provider.dart';
import '../../services/database_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/profile_image_service.dart';
import '../../utils/marker_generator.dart';
import '../widgets/adaptive_map_view.dart';
import '../widgets/buzzing_dot.dart';
import 'location_history_screen.dart';
import 'family_chat_screen.dart';

class MemberMapScreen extends StatefulWidget {
  final FamilyMemberModel member;
  final LocationDetailsModel? initialLocation;

  const MemberMapScreen({
    super.key,
    required this.member,
    this.initialLocation,
  });

  @override
  State<MemberMapScreen> createState() => _MemberMapScreenState();
}

class _MemberMapScreenState extends State<MemberMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _locationSubscription;
  LocationDetailsModel? _currentLocation;
  BitmapDescriptor? _customMarkerIcon;
  File? _profileImageFile;
  String _resolvedAddress = '';

  // Live Tracking Polyline Coordinates & Update Points
  final List<LatLng> _liveTrailPoints = [];
  final List<LocationDetailsModel> _sessionUpdates = [];
  final Set<Polyline> _polylines = {};
  final List<AdaptivePolyline> _adaptivePolylines = [];
  MapType _currentMapType = MapType.normal;
  bool _autoFollow = true;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    if (_currentLocation != null &&
        (_currentLocation!.latitude != 0.0 || _currentLocation!.longitude != 0.0)) {
      _sessionUpdates.add(_currentLocation!);
      _liveTrailPoints.add(LatLng(_currentLocation!.latitude, _currentLocation!.longitude));
    }
    _loadProfileAndMarker();
    _subscribeToLiveLocation();
  }

  Future<void> _loadProfileAndMarker() async {
    final photo =
        await ProfileImageService.getProfileImageFile(widget.member.mobile);
    if (mounted) {
      setState(() => _profileImageFile = photo);
    }

    final icon = await MarkerGenerator.createCustomMemberMarker(
      name: widget.member.name,
      pinColor: AppColors.primary,
      localPhotoPath: photo?.path,
    );

    if (mounted) {
      setState(() => _customMarkerIcon = icon);
    }

    if (_currentLocation != null) {
      _resolveAddress(_currentLocation!.latitude, _currentLocation!.longitude);
    }
  }

  void _clearAndResetTrail() {
    setState(() {
      _sessionUpdates.clear();
      _liveTrailPoints.clear();
      if (_currentLocation != null &&
          (_currentLocation!.latitude != 0.0 || _currentLocation!.longitude != 0.0)) {
        _sessionUpdates.add(_currentLocation!);
        _liveTrailPoints.add(
            LatLng(_currentLocation!.latitude, _currentLocation!.longitude));
      }
      _updatePolylineSet();
    });
  }

  void _updatePolylineSet() {
    if (_liveTrailPoints.length < 2) {
      _polylines.clear();
      _adaptivePolylines.clear();
      return;
    }

    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('live_tracking_trail'),
        points: List.from(_liveTrailPoints),
        color: AppColors.primary,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );

    _adaptivePolylines.clear();
    _adaptivePolylines.add(
      AdaptivePolyline(
        id: 'live_tracking_trail',
        points: _liveTrailPoints.map((p) => ll.LatLng(p.latitude, p.longitude)).toList(),
        color: AppColors.primary,
        strokeWidth: 5.0,
      ),
    );
  }

  void _resolveAddress(double lat, double lng) {
    if (lat != 0.0 || lng != 0.0) {
      GeocodingService.getAddressFromCoordinates(lat, lng).then((addr) {
        if (mounted && addr.isNotEmpty) {
          setState(() => _resolvedAddress = addr);
        }
      });
    }
  }

  void _subscribeToLiveLocation() {
    _locationSubscription = _dbService
        .streamLocationDetails(widget.member.mobile)
        .listen((loc) {
      if (loc != null && mounted) {
        final hasCoords = loc.latitude != 0.0 && loc.longitude != 0.0;
        final newLatLng = LatLng(loc.latitude, loc.longitude);

        setState(() {
          _currentLocation = loc;
          if (hasCoords) {
            // Append new update marker and trail point if moved
            if (_sessionUpdates.isEmpty) {
              _sessionUpdates.add(loc);
              _liveTrailPoints.add(newLatLng);
            } else {
              final last = _sessionUpdates.last;
              if ((last.latitude - loc.latitude).abs() > 0.00001 ||
                  (last.longitude - loc.longitude).abs() > 0.00001) {
                _sessionUpdates.add(loc);
                _liveTrailPoints.add(newLatLng);
              } else {
                _sessionUpdates.last = loc;
              }
            }
            _updatePolylineSet();
          }
        });

        if (hasCoords) {
          _resolveAddress(loc.latitude, loc.longitude);
          if (_autoFollow) {
            _animateCamera(loc.latitude, loc.longitude);
          }
        }
      }
    });
  }

  Future<void> _animateCamera(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) return;
    try {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: 16,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _fitTrailBounds() async {
    if (_liveTrailPoints.isEmpty) {
      if (_currentLocation != null) {
        _animateCamera(
            _currentLocation!.latitude, _currentLocation!.longitude);
      }
      return;
    }

    if (_liveTrailPoints.length == 1) {
      _animateCamera(
          _liveTrailPoints.first.latitude, _liveTrailPoints.first.longitude);
      return;
    }

    try {
      final GoogleMapController controller = await _controller.future;
      double minLat = _liveTrailPoints.first.latitude;
      double maxLat = _liveTrailPoints.first.latitude;
      double minLng = _liveTrailPoints.first.longitude;
      double maxLng = _liveTrailPoints.first.longitude;

      for (var p in _liveTrailPoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
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
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentLocation?.latitude ?? 17.3850;
    final lng = _currentLocation?.longitude ?? 78.4867;
    final pos = LatLng(lat, lng);

    final formattedTime = _currentLocation != null && _currentLocation!.timeStamp > 0
        ? DateFormat('MMM dd, yyyy • hh:mm:ss a').format(
            DateTime.fromMillisecondsSinceEpoch(_currentLocation!.timeStamp),
          )
        : (_currentLocation?.date.isNotEmpty == true
            ? _currentLocation!.date
            : 'Recently');

    final displayAddress = _resolvedAddress.isNotEmpty
        ? _resolvedAddress
        : (_currentLocation?.address.isNotEmpty == true
            ? _currentLocation!.address
            : 'Fetching street address...');

    // Generate markers for EVERY location update
    final markers = <Marker>{};

    for (int i = 0; i < _sessionUpdates.length; i++) {
      final u = _sessionUpdates[i];
      if (u.latitude == 0.0 && u.longitude == 0.0) continue;

      final isCurrent = i == _sessionUpdates.length - 1;
      final isStart = i == 0;
      final dateStr = u.date.isNotEmpty
          ? u.date
          : (u.timeStamp > 0
              ? DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(u.timeStamp))
              : DateFormat('MMM dd, yyyy').format(DateTime.now()));

      final timeStr = u.timeStamp > 0
          ? DateFormat('hh:mm:ss a').format(
              DateTime.fromMillisecondsSinceEpoch(u.timeStamp),
            )
          : '';

      final addrStr = u.address.isNotEmpty
          ? u.address
          : (isCurrent && _resolvedAddress.isNotEmpty ? _resolvedAddress : 'Lat: ${u.latitude.toStringAsFixed(5)}, Lng: ${u.longitude.toStringAsFixed(5)}');

      if (isCurrent) {
        // Current Latest Position Marker
        markers.add(
          Marker(
            markerId: MarkerId(widget.member.mobile),
            position: LatLng(u.latitude, u.longitude),
            zIndexInt: 100,
            icon: _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(
              title: '📍 ${widget.member.name} (Current)',
              snippet: '📅 $dateStr • 🕒 $timeStr\n📍 $addrStr\n⚡ Battery: ${u.batteryPercentage}%',
            ),
          ),
        );
      } else if (isStart) {
        // Start Origin Position Marker
        markers.add(
          Marker(
            markerId: const MarkerId('live_step_start'),
            position: LatLng(u.latitude, u.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            zIndexInt: 30,
            infoWindow: InfoWindow(
              title: '🟢 Start Location (#1)',
              snippet: '📅 $dateStr • 🕒 $timeStr\n📍 $addrStr\n⚡ Battery: ${u.batteryPercentage}%',
            ),
          ),
        );
      } else {
        // Intermediate Update Marker for every new update
        markers.add(
          Marker(
            markerId: MarkerId('live_step_$i'),
            position: LatLng(u.latitude, u.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            zIndexInt: 10,
            infoWindow: InfoWindow(
              title: '🔵 Location Update #${i + 1}',
              snippet: '📅 $dateStr • 🕒 $timeStr\n📍 $addrStr\n⚡ Battery: ${u.batteryPercentage}%',
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member.name),
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
            icon: const Icon(Icons.history_rounded),
            tooltip: 'View Full History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationHistoryScreen(
                    member: widget.member,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          AdaptiveMapView(
            initialLat: pos.latitude,
            initialLng: pos.longitude,
            initialZoom: 15,
            mapType: _currentMapType,
            points: _sessionUpdates.asMap().entries.map((entry) {
              final i = entry.key;
              final u = entry.value;
              final isCurrent = i == _sessionUpdates.length - 1;
              final isStart = i == 0;
              return AdaptiveMapPoint(
                id: isCurrent ? widget.member.mobile : 'live_step_$i',
                latitude: u.latitude,
                longitude: u.longitude,
                title: isCurrent
                    ? '${widget.member.name} (Current)'
                    : (isStart ? '🟢 Start Location (#1)' : '🔵 Update #${i + 1}'),
                snippet: u.address.isNotEmpty
                    ? u.address
                    : (isCurrent && _resolvedAddress.isNotEmpty ? _resolvedAddress : ''),
                pinColor: isCurrent
                    ? AppColors.primary
                    : (isStart ? AppColors.success : AppColors.accent),
              );
            }).where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList(),
            polylines: _adaptivePolylines,
            googleMarkers: markers,
            googlePolylines: _polylines,
            onGoogleMapCreated: (controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
            },
          ),

          // Top Live Status & Trail Badge
          Positioned(
            top: 16,
            left: 20,
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      _liveTrailPoints.length > 1
                          ? 'LIVE MOVEMENT (${_liveTrailPoints.length} PTS)'
                          : 'LIVE TRACKING ACTIVE',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Floating Map Quick Actions (Auto-Follow, Fit Trail, & Reset Trail)
          Positioned(
            top: 16,
            right: 16,
            child: RepaintBoundary(
              child: Column(
                children: [
                  // Re-center / Auto Follow Toggle
                  FloatingActionButton.small(
                    heroTag: 'btn_auto_follow',
                    backgroundColor: _autoFollow ? AppColors.primary : Colors.white,
                    foregroundColor: _autoFollow ? Colors.white : AppColors.textPrimary,
                    elevation: 4,
                    onPressed: () {
                      setState(() => _autoFollow = !_autoFollow);
                      if (_autoFollow && _currentLocation != null) {
                        _animateCamera(
                            _currentLocation!.latitude, _currentLocation!.longitude);
                      }
                    },
                    child: Icon(
                      _autoFollow
                          ? Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Fit Full Trail Route (when moving)
                  if (_liveTrailPoints.length > 1) ...[
                    FloatingActionButton.small(
                      heroTag: 'btn_fit_trail',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 4,
                      onPressed: () {
                        setState(() => _autoFollow = false);
                        _fitTrailBounds();
                      },
                      child: const Icon(Icons.route_rounded, size: 20),
                    ),
                    const SizedBox(height: 8),

                    // Reset / Start Fresh Session Trail
                    FloatingActionButton.small(
                      heroTag: 'btn_reset_trail',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.danger,
                      elevation: 4,
                      tooltip: 'Reset Trail',
                      onPressed: _clearAndResetTrail,
                      child: const Icon(Icons.restart_alt_rounded, size: 20),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Info Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: RepaintBoundary(
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppColors.primaryLight.withValues(alpha: 0.2),
                            backgroundImage: _profileImageFile != null
                                ? FileImage(_profileImageFile!)
                                : null,
                            child: _profileImageFile == null
                                ? Text(
                                    widget.member.name.isNotEmpty
                                        ? widget.member.name[0].toUpperCase()
                                        : 'M',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.member.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  widget.member.mobile,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_currentLocation != null &&
                              _currentLocation!.batteryPercentage > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _currentLocation!.batteryPercentage > 20
                                    ? AppColors.successBg
                                    : AppColors.dangerBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _currentLocation!.batteryPercentage > 20
                                        ? Icons.battery_full_rounded
                                        : Icons.battery_alert_rounded,
                                    size: 14,
                                    color: _currentLocation!.batteryPercentage > 20
                                        ? AppColors.success
                                        : AppColors.danger,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_currentLocation!.batteryPercentage}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _currentLocation!.batteryPercentage > 20
                                          ? AppColors.success
                                          : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: AppColors.cardBorder),
                      const SizedBox(height: 8),

                      // 1. Lat & Lng Coordinates
                      Row(
                        children: [
                          const Icon(
                            Icons.gps_fixed_rounded,
                            size: 14,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // 2. Full Street Address (Below Lat & Lng)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              displayAddress,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // 3. Last Updated
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
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

                      // Call & SMS & History buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _makeCall(widget.member.mobile),
                              icon: const Icon(Icons.call_rounded, size: 16),
                              label: const Text('Call'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (ctx) {
                                final hasUnread = ctx.watch<FamilyProvider>().hasUnreadForMember(widget.member.mobile);
                                return OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FamilyChatScreen(
                                          targetMember: widget.member,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: BuzzingBadge(
                                    showBadge: hasUnread,
                                    dotSize: 7,
                                    top: -2,
                                    right: -2,
                                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                  ),
                                  label: const Text('Chat'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
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
                                      member: widget.member,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.route_rounded, size: 16),
                              label: const Text('History'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
