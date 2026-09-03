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

  AdaptiveMapPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.snippet = '',
    this.pinColor = AppColors.primary,
    this.onTap,
    this.localPhotoPath,
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
  final List<AdaptiveMapPoint> points;
  final List<AdaptivePolyline> polylines;
  final Set<gmaps.Marker>? googleMarkers;
  final Set<gmaps.Polyline>? googlePolylines;
  final Function(gmaps.GoogleMapController)? onGoogleMapCreated;

  const AdaptiveMapView({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 14.0,
    this.points = const [],
    this.polylines = const [],
    this.googleMarkers,
    this.googlePolylines,
    this.onGoogleMapCreated,
  });

  @override
  State<AdaptiveMapView> createState() => _AdaptiveMapViewState();
}

class _AdaptiveMapViewState extends State<AdaptiveMapView> {
  final fmap.MapController _flutterMapController = fmap.MapController();

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
            // Libre / OpenStreetMap High-Resolution Tile Layer
            fmap.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.mat.familytrack',
              maxZoom: 19,
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

            // Custom Interactive Libre Markers Layer
            if (widget.points.isNotEmpty)
              fmap.MarkerLayer(
                markers: widget.points.map((p) {
                  return fmap.Marker(
                    point: ll.LatLng(p.latitude, p.longitude),
                    width: 120,
                    height: 80,
                    child: GestureDetector(
                      onTap: p.onTap,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Name Label Pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: p.pinColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              p.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Pin Avatar / Icon
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: p.pinColor, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                p.title.isNotEmpty
                                    ? p.title[0].toUpperCase()
                                    : 'F',
                                style: TextStyle(
                                  color: p.pinColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

        // Libre Map Attribution & Controls
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 5),
                Text(
                  'Free Libre Map',
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
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(widget.initialLat, widget.initialLng),
        zoom: widget.initialZoom,
      ),
      markers: widget.googleMarkers ?? {},
      polylines: widget.googlePolylines ?? {},
      onMapCreated: widget.onGoogleMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
