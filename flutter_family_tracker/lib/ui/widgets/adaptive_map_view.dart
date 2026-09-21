import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../../constants/app_colors.dart';

class AdaptiveMapPoint {
  final String id;
  final double latitude;
  final double longitude;
  final String title;
  final String snippet;
  final Color pinColor;
  final VoidCallback? onTap;
  final String? localPhotoPath;
  final File? photoFile;
  final bool isSelected;
  final bool isMoving;
  final bool isUpdating;
  final String lastUpdated;
  final int batteryPercentage;
  final bool isPlace;
  final IconData? placeIcon;

  AdaptiveMapPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.snippet = '',
    this.pinColor = AppColors.primary,
    this.onTap,
    this.localPhotoPath,
    this.photoFile,
    this.isSelected = false,
    this.isMoving = false,
    this.isUpdating = false,
    this.lastUpdated = '',
    this.batteryPercentage = 0,
    this.isPlace = false,
    this.placeIcon,
  });
}

class AdaptivePolyline {
  final String id;
  final List<ll.LatLng> points;
  final Color color;
  final double strokeWidth;

  AdaptivePolyline({
    required this.id,
    required this.points,
    this.color = AppColors.primary,
    this.strokeWidth = 4.0,
  });
}

class AdaptiveMapView extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final gmaps.MapType mapType;
  final List<AdaptiveMapPoint> points;
  final List<AdaptivePolyline> polylines;
  final Set<gmaps.Marker>? googleMarkers;
  final Set<gmaps.Polyline>? googlePolylines;
  final Set<gmaps.Circle>? googleCircles;
  final Function(gmaps.GoogleMapController)? onGoogleMapCreated;
  final fmap.MapController? flutterMapController;

  const AdaptiveMapView({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 14.0,
    this.mapType = gmaps.MapType.normal,
    this.points = const [],
    this.polylines = const [],
    this.googleMarkers,
    this.googlePolylines,
    this.googleCircles,
    this.onGoogleMapCreated,
    this.flutterMapController,
  });

  @override
  State<AdaptiveMapView> createState() => _AdaptiveMapViewState();
}

class _AdaptiveMapViewState extends State<AdaptiveMapView>
    with SingleTickerProviderStateMixin {
  fmap.MapController? _flutterMapController;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _flutterMapController = widget.flutterMapController ?? fmap.MapController();
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat(reverse: true);
      _pulseAnimation = CurvedAnimation(
        parent: _pulseController!,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildLibreOpenStreetMap();
    } else {
      return _buildGoogleMap();
    }
  }

  // 100% Free OpenStreetMap / Libre Map for Web
  Widget _buildLibreOpenStreetMap() {
    final center = ll.LatLng(widget.initialLat, widget.initialLng);

    return Stack(
      children: [
        fmap.FlutterMap(
          mapController: _flutterMapController,
          options: fmap.MapOptions(
            initialCenter: center,
            initialZoom: widget.initialZoom,
            interactionOptions: const fmap.InteractionOptions(
              flags: fmap.InteractiveFlag.all,
            ),
          ),
          children: [
            // Google Map Tile Layer
            fmap.TileLayer(
              urlTemplate: widget.mapType == gmaps.MapType.hybrid || widget.mapType == gmaps.MapType.satellite
                  ? 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                  : widget.mapType == gmaps.MapType.terrain
                      ? 'https://mt{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}'
                      : 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              subdomains: const ['0', '1', '2', '3'],
              userAgentPackageName: 'com.mat.familytrack',
              maxZoom: 20,
            ),

            // Polyline Layer for Routes / History
            if (widget.polylines.isNotEmpty)
              fmap.PolylineLayer(
                polylines: widget.polylines.map((poly) {
                  return fmap.Polyline(
                    points: poly.points,
                    color: poly.color,
                    strokeWidth: poly.strokeWidth,
                  );
                }).toList(),
              ),

            // Geofence Circle Overlay Layer for Safe Places
            if (widget.googleCircles != null && widget.googleCircles!.isNotEmpty)
              fmap.CircleLayer(
                circles: widget.googleCircles!.map((c) {
                  return fmap.CircleMarker(
                    point: ll.LatLng(c.center.latitude, c.center.longitude),
                    radius: c.radius,
                    useRadiusInMeter: true,
                    color: c.fillColor,
                    borderColor: c.strokeColor,
                    borderStrokeWidth: c.strokeWidth.toDouble(),
                  );
                }).toList(),
              ),

            // Custom Interactive Libre Markers Layer with Member Avatars & Live Status
            if (widget.points.isNotEmpty)
              fmap.MarkerLayer(
                markers: widget.points.map((p) {
                  final isSelected = p.isSelected;
                  final pinColor = isSelected ? const Color(0xFFF59E0B) : p.pinColor;
                  final avatarSize = isSelected ? 42.0 : 34.0;
                  final needleHeight = isSelected ? 20.0 : 16.0;
                  final needleWidth = isSelected ? 3.5 : 2.8;

                  File? validPhotoFile = p.photoFile;
                  if (validPhotoFile == null && p.localPhotoPath != null && p.localPhotoPath!.isNotEmpty) {
                    try {
                      final f = File(p.localPhotoPath!);
                      if (f.existsSync()) validPhotoFile = f;
                    } catch (_) {}
                  }

                  String detailsText = '';
                  if (p.isMoving) {
                    detailsText = '🚗 Moving${p.lastUpdated.isNotEmpty ? " • ${p.lastUpdated}" : ""}';
                  } else if (p.lastUpdated.isNotEmpty) {
                    detailsText = '🕒 ${p.lastUpdated}${p.batteryPercentage > 0 ? " • ⚡${p.batteryPercentage}%" : ""}';
                  } else if (p.batteryPercentage > 0) {
                    detailsText = '⚡ ${p.batteryPercentage}% Battery';
                  } else if (p.snippet.isNotEmpty) {
                    detailsText = p.snippet;
                  }

                  final avatarCore = Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pinColor,
                          border: Border.all(
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.white,
                            width: isSelected ? 3.0 : 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                                  : Colors.black.withValues(alpha: 0.35),
                              blurRadius: isSelected ? 10 : 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: p.isPlace
                            ? Center(
                                child: Icon(
                                  p.placeIcon ?? Icons.shield_rounded,
                                  color: Colors.white,
                                  size: avatarSize * 0.58,
                                ),
                              )
                            : ClipOval(
                                child: !kIsWeb && validPhotoFile != null
                                    ? Image.file(
                                        validPhotoFile,
                                        width: avatarSize,
                                        height: avatarSize,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.network(
                                        'https://ui-avatars.com/api/?name=${Uri.encodeComponent(p.title.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ''))}&background=${pinColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}&color=ffffff&size=128&bold=true',
                                        width: avatarSize,
                                        height: avatarSize,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Center(
                                          child: Text(
                                            p.title.isNotEmpty
                                                ? p.title.replaceAll(RegExp(r'[^a-zA-Z]'), '')[0].toUpperCase()
                                                : 'M',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: isSelected ? 18 : 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                      ),
                      if (p.isMoving)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  );

                  return fmap.Marker(
                    point: ll.LatLng(p.latitude, p.longitude),
                    width: isSelected ? 170 : 150,
                    height: isSelected ? 115 : 100,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: p.onTap,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 1. Name & Last Updated Details Pill (Above Pin)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSelected ? 8 : 6,
                              vertical: detailsText.isNotEmpty ? 3 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF0F172A).withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFF59E0B)
                                    : Colors.white.withValues(alpha: 0.35),
                                width: isSelected ? 1.6 : 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                                      : Colors.black.withValues(alpha: 0.35),
                                  blurRadius: isSelected ? 8 : 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  p.title,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFFFCD34D) : Colors.white,
                                    fontSize: isSelected ? 11 : 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (detailsText.isNotEmpty)
                                  Text(
                                    detailsText,
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFFDE68A)
                                          : const Color(0xFFCBD5E1),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),

                          // 2. Avatar Head with Pulsing Radar Ring & Image
                          if (_pulseAnimation != null && (p.isMoving || p.isUpdating))
                            AnimatedBuilder(
                              animation: _pulseAnimation!,
                              builder: (context, child) {
                                final pulseSpread = _pulseAnimation!.value * 18.0;
                                final pulseOpacity = (1.0 - _pulseAnimation!.value) * 0.70;

                                return Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: avatarSize + pulseSpread,
                                      height: avatarSize + pulseSpread,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (p.isMoving
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF3B82F6))
                                            .withValues(alpha: pulseOpacity),
                                      ),
                                    ),
                                    child!,
                                  ],
                                );
                              },
                              child: avatarCore,
                            )
                          else
                            avatarCore,

                          // 3. Pin Needle / Stick (Metallic Grey gradient pointing straight down)
                          Container(
                            width: needleWidth,
                            height: needleHeight,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Color(0xFF64748B),
                                  Color(0xFF334155),
                                  Color(0xFF1E293B),
                                ],
                              ),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(1.5),
                                bottomRight: Radius.circular(1.5),
                              ),
                            ),
                          ),

                          // Ground Contact Shadow at Needle Tip
                          Container(
                            width: 8,
                            height: 2.5,
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.all(Radius.elliptical(8, 2.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),

        // Map Attribution & Controls
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 5),
                Text(
                  'Google Maps',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Zoom In / Zoom Out Controls
        Positioned(
          bottom: 24,
          right: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'libre_zoom_in',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  if (_flutterMapController != null) {
                    final zoom = _flutterMapController!.camera.zoom + 1;
                    _flutterMapController!.move(
                      _flutterMapController!.camera.center,
                      zoom,
                    );
                  }
                },
                child: const Icon(Icons.add_rounded),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'libre_zoom_out',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  if (_flutterMapController != null) {
                    final zoom = _flutterMapController!.camera.zoom - 1;
                    _flutterMapController!.move(
                      _flutterMapController!.camera.center,
                      zoom,
                    );
                  }
                },
                child: const Icon(Icons.remove_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Google Maps for Android / iOS Native
  Widget _buildGoogleMap() {
    final Set<gmaps.Marker> markers;
    if (widget.googleMarkers != null && widget.googleMarkers!.isNotEmpty) {
      markers = widget.googleMarkers!;
    } else {
      markers = widget.points
          .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
          .map((p) {
            return gmaps.Marker(
              markerId: gmaps.MarkerId(p.id),
              position: gmaps.LatLng(p.latitude, p.longitude),
              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                p.isSelected
                    ? gmaps.BitmapDescriptor.hueOrange
                    : gmaps.BitmapDescriptor.hueAzure,
              ),
              infoWindow: gmaps.InfoWindow(
                title: p.title,
                snippet: p.snippet,
              ),
              onTap: p.onTap,
            );
          }).toSet();
    }

    return gmaps.GoogleMap(
      mapType: widget.mapType,
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(widget.initialLat, widget.initialLng),
        zoom: widget.initialZoom,
      ),
      markers: markers,
      polylines: widget.googlePolylines ?? const <gmaps.Polyline>{},
      circles: widget.googleCircles ?? const <gmaps.Circle>{},
      onMapCreated: widget.onGoogleMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
