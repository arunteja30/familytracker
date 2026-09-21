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
  final bool isSelected;

  AdaptiveMapPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.snippet = '',
    this.pinColor = AppColors.primary,
    this.onTap,
    this.localPhotoPath,
    this.isSelected = false,
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

class _AdaptiveMapViewState extends State<AdaptiveMapView> {
  late final fmap.MapController _flutterMapController;

  @override
  void initState() {
    super.initState();
    _flutterMapController = widget.flutterMapController ?? fmap.MapController();
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

            // Custom Interactive Libre Markers Layer with 3D Pushpin Stick Markers
            if (widget.points.isNotEmpty)
              fmap.MarkerLayer(
                markers: widget.points.map((p) {
                  final isSelected = p.isSelected;
                  final pinColor = isSelected ? const Color(0xFFF59E0B) : p.pinColor;
                  final headSize = isSelected ? 32.0 : 26.0;
                  final needleHeight = isSelected ? 22.0 : 18.0;
                  final needleWidth = isSelected ? 3.5 : 2.8;

                  return fmap.Marker(
                    point: ll.LatLng(p.latitude, p.longitude),
                    width: isSelected ? 150 : 130,
                    height: isSelected ? 100 : 88,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: p.onTap,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Name / Status Label Pill (Above the Pin)
                          if (p.title.isNotEmpty)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 2),
                              padding: EdgeInsets.symmetric(
                                horizontal: isSelected ? 8 : 6,
                                vertical: isSelected ? 3 : 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFF0F172A).withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFF59E0B)
                                      : Colors.white.withValues(alpha: 0.35),
                                  width: isSelected ? 1.5 : 0.8,
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
                              child: Text(
                                p.title,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFFFCD34D) : Colors.white,
                                  fontSize: isSelected ? 11 : 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          // 3D Pushpin (Spherical Head with Specular Highlight + Metallic Needle + Shadow)
                          SizedBox(
                            width: isSelected ? 48 : 40,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 3D Spherical Head
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: headSize,
                                  height: headSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      center: const Alignment(-0.35, -0.35),
                                      radius: 0.85,
                                      colors: [
                                        Color.lerp(pinColor, Colors.white, 0.45)!,
                                        pinColor,
                                        Color.lerp(pinColor, Colors.black, 0.45)!,
                                      ],
                                      stops: const [0.0, 0.55, 1.0],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isSelected
                                            ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                                            : Colors.black.withValues(alpha: 0.35),
                                        blurRadius: isSelected ? 10 : 5,
                                        offset: const Offset(0, 3),
                                      ),
                                      if (isSelected)
                                        const BoxShadow(
                                          color: Color(0xFFF59E0B),
                                          blurRadius: 10,
                                          spreadRadius: 1.5,
                                        ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Specular Highlight Spot (Exact match with reference image)
                                      Positioned(
                                        top: headSize * 0.16,
                                        left: headSize * 0.18,
                                        child: Container(
                                          width: headSize * 0.30,
                                          height: headSize * 0.30,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(alpha: 0.72),
                                          ),
                                        ),
                                      ),
                                      // Inner icon (Start / End / Star)
                                      if (p.title.startsWith('🟢'))
                                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: headSize * 0.52)
                                      else if (p.title.startsWith('🏁'))
                                        Icon(Icons.flag_rounded, color: Colors.white, size: headSize * 0.52)
                                      else if (isSelected)
                                        Icon(Icons.star_rounded, color: Colors.white, size: headSize * 0.52),
                                    ],
                                  ),
                                ),

                                // Pin Needle / Stick (Metallic Grey gradient pointing straight down)
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
                                  width: 7,
                                  height: 2,
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.all(Radius.elliptical(7, 2)),
                                  ),
                                ),
                              ],
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
                  final zoom = _flutterMapController.camera.zoom + 1;
                  _flutterMapController.move(
                    _flutterMapController.camera.center,
                    zoom,
                  );
                },
                child: const Icon(Icons.add_rounded),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'libre_zoom_out',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  final zoom = _flutterMapController.camera.zoom - 1;
                  _flutterMapController.move(
                    _flutterMapController.camera.center,
                    zoom,
                  );
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
    return gmaps.GoogleMap(
      mapType: widget.mapType,
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(widget.initialLat, widget.initialLng),
        zoom: widget.initialZoom,
      ),
      markers: widget.googleMarkers ?? {},
      polylines: widget.googlePolylines ?? {},
      circles: widget.googleCircles ?? {},
      onMapCreated: widget.onGoogleMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
