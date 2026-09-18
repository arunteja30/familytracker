import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import '../../constants/app_colors.dart';
import '../../models/geofence_place_model.dart';

class PlacePickerResult {
  final double latitude;
  final double longitude;
  final double radiusMeters;

  PlacePickerResult({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });
}

class PlacePickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final double initialRadius;
  final PlaceCategory category;
  final String placeName;

  const PlacePickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialRadius = 150.0,
    this.category = PlaceCategory.home,
    this.placeName = '',
  });

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  late double _currentLat;
  late double _currentLng;
  late double _radius;
  gmaps.GoogleMapController? _googleMapController;
  final fmap.MapController _flutterMapController = fmap.MapController();

  gmaps.MapType _mapType = gmaps.MapType.normal;
  bool _isLoadingGps = false;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLat;
    _currentLng = widget.initialLng;
    _radius = widget.initialRadius;

    // If initial lat/lng are 0, fetch current position
    if (_currentLat == 0.0 && _currentLng == 0.0) {
      _locateUser(animateCamera: true);
    }
  }

  Future<void> _locateUser({bool animateCamera = true}) async {
    setState(() => _isLoadingGps = true);
    try {
      Position? pos;
      if (!kIsWeb) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
      pos ??= await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      if (mounted) {
        setState(() {
          _currentLat = pos!.latitude;
          _currentLng = pos.longitude;
          _isLoadingGps = false;
        });

        if (animateCamera) {
          if (!kIsWeb && _googleMapController != null) {
            _googleMapController!.animateCamera(
              gmaps.CameraUpdate.newLatLngZoom(
                gmaps.LatLng(pos.latitude, pos.longitude),
                16.5,
              ),
            );
          } else if (kIsWeb) {
            _flutterMapController.move(ll.LatLng(pos.latitude, pos.longitude), 16.5);
          }
        }
      }
    } catch (e) {
      debugPrint('[PlacePicker] GPS locate error: $e');
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _onMapTapped(double lat, double lng) {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
    });

    if (!kIsWeb && _googleMapController != null) {
      _googleMapController!.animateCamera(
        gmaps.CameraUpdate.newLatLng(gmaps.LatLng(lat, lng)),
      );
    } else if (kIsWeb) {
      _flutterMapController.move(ll.LatLng(lat, lng), _flutterMapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.category.color;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick Safe Zone Location',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              widget.placeName.isNotEmpty ? widget.placeName : widget.category.displayName,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _mapType == gmaps.MapType.normal ? 'Satellite View' : 'Normal View',
            icon: Icon(
              _mapType == gmaps.MapType.normal ? Icons.satellite_alt_rounded : Icons.map_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _mapType = _mapType == gmaps.MapType.normal ? gmaps.MapType.hybrid : gmaps.MapType.normal;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Live Interactive Map
          Positioned.fill(
            child: kIsWeb ? _buildWebMap(themeColor) : _buildNativeGoogleMap(themeColor),
          ),

          // 2. Center Target Crosshair & Pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 38), // Center over pin tip
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(widget.category.icon, color: Colors.white, size: 24),
                  ),
                  CustomPaint(
                    size: const Size(12, 10),
                    painter: _TrianglePainter(color: themeColor),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Instruction Pill
          Positioned(
            top: 14,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 16, color: themeColor),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Drag map or tap to place the center of the safe zone',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. GPS Quick Locate FAB
          Positioned(
            right: 16,
            bottom: 240,
            child: FloatingActionButton.small(
              heroTag: 'gps_locate_btn',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 4,
              onPressed: _isLoadingGps ? null : () => _locateUser(animateCamera: true),
              child: _isLoadingGps
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // 5. Bottom Settings & Confirmation Card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
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
                    const SizedBox(height: 12),

                    // Coordinates & Radius Info Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 14, color: themeColor),
                              const SizedBox(width: 4),
                              Text(
                                '${_currentLat.toStringAsFixed(5)}, ${_currentLng.toStringAsFixed(5)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            'Radius: ${_radius.round()}m',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Radius Slider
                    Row(
                      children: [
                        const Text('Radius:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        Expanded(
                          child: Slider(
                            value: _radius,
                            min: 50.0,
                            max: 1000.0,
                            divisions: 19,
                            activeColor: themeColor,
                            label: '${_radius.round()}m',
                            onChanged: (val) => setState(() => _radius = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Confirm Selection Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_currentLat == 0.0 && _currentLng == 0.0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select a valid location on the map')),
                            );
                            return;
                          }

                          Navigator.pop(
                            context,
                            PlacePickerResult(
                              latitude: _currentLat,
                              longitude: _currentLng,
                              radiusMeters: _radius,
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text(
                          'Confirm Safe Zone Location',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
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

  // Native Google Maps Builder
  Widget _buildNativeGoogleMap(Color themeColor) {
    final latLng = gmaps.LatLng(_currentLat, _currentLng);

    final Set<gmaps.Circle> circles = {
      gmaps.Circle(
        circleId: const gmaps.CircleId('picker_geofence_preview'),
        center: latLng,
        radius: _radius,
        fillColor: themeColor.withValues(alpha: 0.22),
        strokeColor: themeColor.withValues(alpha: 0.85),
        strokeWidth: 2,
      ),
    };

    return gmaps.GoogleMap(
      mapType: _mapType,
      initialCameraPosition: gmaps.CameraPosition(
        target: latLng,
        zoom: 16.0,
      ),
      circles: circles,
      onMapCreated: (controller) => _googleMapController = controller,
      onCameraMove: (pos) {
        setState(() {
          _currentLat = pos.target.latitude;
          _currentLng = pos.target.longitude;
        });
      },
      onTap: (point) => _onMapTapped(point.latitude, point.longitude),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  // Web OpenStreetMap Builder
  Widget _buildWebMap(Color themeColor) {
    final center = ll.LatLng(_currentLat, _currentLng);

    return fmap.FlutterMap(
      mapController: _flutterMapController,
      options: fmap.MapOptions(
        initialCenter: center,
        initialZoom: 16.0,
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture) {
            setState(() {
              _currentLat = pos.center.latitude;
              _currentLng = pos.center.longitude;
            });
          }
        },
        onTap: (_, point) => _onMapTapped(point.latitude, point.longitude),
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: _mapType == gmaps.MapType.hybrid || _mapType == gmaps.MapType.satellite
              ? 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
              : 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
          subdomains: const ['0', '1', '2', '3'],
          userAgentPackageName: 'com.mat.familytrack',
          maxZoom: 20,
        ),
        fmap.CircleLayer(
          circles: [
            fmap.CircleMarker(
              point: center,
              radius: _radius,
              useRadiusInMeter: true,
              color: themeColor.withValues(alpha: 0.22),
              borderColor: themeColor.withValues(alpha: 0.85),
              borderStrokeWidth: 2,
            ),
          ],
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
