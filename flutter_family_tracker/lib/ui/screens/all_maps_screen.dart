import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/geocoding_service.dart';
import '../../services/profile_image_service.dart';
import '../../utils/marker_generator.dart';
import '../widgets/adaptive_map_view.dart';
import 'location_history_screen.dart';

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
  MapType _currentMapType = MapType.normal;
  final Set<Marker> _markers = {};
  FamilyMemberModel? _selectedMember;
  final Map<String, String> _resolvedAddresses = {};
  final Map<String, File?> _memberPhotos = {};

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
    if (widget.members.isNotEmpty) {
      _selectedMember = widget.members.first;
    }
    _loadPhotosAndBuildMarkers();
  }

  Future<void> _loadPhotosAndBuildMarkers() async {
    final Set<Marker> newMarkers = {};

    for (int i = 0; i < widget.members.length; i++) {
      final member = widget.members[i];
      final loc = widget.locations[member.mobile];
      final color = _markerColors[i % _markerColors.length];

      // Load local photo
      final photoFile =
          await ProfileImageService.getProfileImageFile(member.mobile);
      _memberPhotos[member.mobile] = photoFile;

      if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
        // Resolve address if missing or coordinate format
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

        newMarkers.add(
          Marker(
            markerId: MarkerId(member.mobile),
            position: LatLng(loc.latitude, loc.longitude),
            icon: customIcon,
            infoWindow: InfoWindow(
              title: member.name,
              snippet: '⚡ ${loc.batteryPercentage}% • $displayAddr\n🕒 $lastUpdated',
            ),
            onTap: () {
              setState(() => _selectedMember = member);
            },
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
      });
    }
  }

  Future<void> _focusMember(FamilyMemberModel member) async {
    final loc = widget.locations[member.mobile];
    if (loc != null && (loc.latitude != 0.0 || loc.longitude != 0.0)) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(loc.latitude, loc.longitude),
            zoom: 16,
          ),
        ),
      );
      setState(() => _selectedMember = member);
    }
  }

  Future<void> _fitAllBounds() async {
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

  Future<void> _sendSms(String phone) async {
    final uri = Uri.parse('sms:$phone');
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
        ? widget.locations[_selectedMember!.mobile]
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
        title: Text('${widget.familyName} Live Map'),
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
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _fitAllBounds,
          ),
        ],
      ),
      body: Stack(
        children: [
          AdaptiveMapView(
            initialLat: initialPos.latitude,
            initialLng: initialPos.longitude,
            initialZoom: 12,
            points: widget.members.map((m) {
              final loc = widget.locations[m.mobile];
              return AdaptiveMapPoint(
                id: m.mobile,
                latitude: loc?.latitude ?? 0.0,
                longitude: loc?.longitude ?? 0.0,
                title: m.name,
                snippet: loc?.address ?? '',
                pinColor: MarkerGenerator.getMarkerColor(m.relationship),
                onTap: () {
                  setState(() {
                    _selectedMember = m;
                  });
                },
              );
            }).where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList(),
            googleMarkers: _markers,
            onGoogleMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
              Future.delayed(const Duration(milliseconds: 600), _fitAllBounds);
            },
          ),

          // Selected Member Comprehensive Floating Card
          if (_selectedMember != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
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
                      // Header Row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                AppColors.primaryLight.withOpacity(0.2),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedMember!.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (selectedLoc != null &&
                                        selectedLoc.batteryPercentage > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selectedLoc.batteryPercentage > 20
                                              ? AppColors.successBg
                                              : AppColors.dangerBg,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              selectedLoc.batteryPercentage > 20
                                                  ? Icons.battery_full_rounded
                                                  : Icons.battery_alert_rounded,
                                              size: 13,
                                              color:
                                                  selectedLoc.batteryPercentage > 20
                                                      ? AppColors.success
                                                      : AppColors.danger,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${selectedLoc.batteryPercentage}%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: selectedLoc
                                                            .batteryPercentage >
                                                        20
                                                    ? AppColors.success
                                                    : AppColors.danger,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  _selectedMember!.mobile,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
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

                      // Full Reverse Geocoded Street Address
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
                              currentAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Exact GPS Coordinates
                      Row(
                        children: [
                          const Icon(
                            Icons.gps_fixed_rounded,
                            size: 14,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            selectedLoc != null && selectedLoc.latitude != 0.0
                                ? 'Lat: ${selectedLoc.latitude.toStringAsFixed(6)}, Lng: ${selectedLoc.longitude.toStringAsFixed(6)}'
                                : 'No GPS Fix',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Last Updated Time
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 14,
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

                      // Quick Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _makeCall(_selectedMember!.mobile),
                              icon: const Icon(Icons.call_rounded, size: 15),
                              label: const Text('Call', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _sendSms(_selectedMember!.mobile),
                              icon: const Icon(Icons.sms_rounded, size: 15),
                              label: const Text('SMS', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
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
                              icon: const Icon(Icons.history_rounded, size: 15),
                              label: const Text('History', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 6),
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

          // Horizontal Member Selector at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.members.length,
                itemBuilder: (context, index) {
                  final member = widget.members[index];
                  final loc = widget.locations[member.mobile];
                  final photo = _memberPhotos[member.mobile];
                  final isSelected = _selectedMember?.mobile == member.mobile;

                  return GestureDetector(
                    onTap: () => _focusMember(member),
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                AppColors.primaryLight.withOpacity(0.2),
                            backgroundImage:
                                photo != null ? FileImage(photo) : null,
                            child: photo == null
                                ? Text(
                                    member.name.isNotEmpty
                                        ? member.name[0].toUpperCase()
                                        : 'M',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  loc != null && loc.batteryPercentage > 0
                                      ? '⚡ ${loc.batteryPercentage}%'
                                      : 'No GPS',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
