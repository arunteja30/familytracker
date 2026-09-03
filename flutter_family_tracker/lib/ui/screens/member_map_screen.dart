import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/profile_image_service.dart';
import '../../utils/marker_generator.dart';
import 'location_history_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
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

  void _resolveAddress(double lat, double lng) {
    if (lat != 0.0 || lng != 0.0) {
      GeocodingService.getAddressFromCoordinates(lat, lng).then((addr) {
        if (mounted) {
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
        setState(() => _currentLocation = loc);
        _resolveAddress(loc.latitude, loc.longitude);
        _animateCamera(loc.latitude, loc.longitude);
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

    final markers = <Marker>{
      if (_currentLocation != null)
        Marker(
          markerId: MarkerId(widget.member.mobile),
          position: pos,
          icon: _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: widget.member.name,
            snippet:
                '$displayAddress\n⚡ ${_currentLocation?.batteryPercentage}%\n🕒 $formattedTime',
          ),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
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
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: pos,
              zoom: 15,
            ),
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) => _controller.complete(controller),
          ),

          // Top Live Badge
          Positioned(
            top: 16,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'LIVE TRACKING ACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Info Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              AppColors.primaryLight.withOpacity(0.2),
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                widget.member.mobile,
                                style: const TextStyle(
                                  fontSize: 13,
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
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.cardBorder),
                    const SizedBox(height: 10),

                    // Full Street Address
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
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Coordinates
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
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Last Updated
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
                    const SizedBox(height: 14),

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
                          child: OutlinedButton.icon(
                            onPressed: () => _sendSms(widget.member.mobile),
                            icon: const Icon(Icons.message_rounded, size: 16),
                            label: const Text('SMS'),
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
        ],
      ),
    );
  }
}
