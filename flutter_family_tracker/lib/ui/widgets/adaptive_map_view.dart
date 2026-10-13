import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../../constants/app_colors.dart';
import '../../services/preferences_service.dart';

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
  final bool isWaypoint;
  final int? waypointNumber;
  final bool isTripStart;
  final bool isTripEnd;

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
    this.isWaypoint = false,
    this.waypointNumber,
    this.isTripStart = false,
    this.isTripEnd = false,
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
  fmap.MapController? _flutterMapController;
  bool _useLibreMap = true;
  String _tileSource = 'google_road'; // 'google_road', 'google_sat', 'google_terrain', 'osm'

  @override
  void initState() {
    super.initState();
    _useLibreMap = PreferencesService.useOpenStreetMap();
    _flutterMapController = widget.flutterMapController ?? fmap.MapController();
  }

  @override
  void dispose() {
    if (widget.flutterMapController == null) {
      _flutterMapController?.dispose();
    }
    super.dispose();
  }

  List<AdaptiveMapPoint> get _effectivePoints {
    if (widget.points.isNotEmpty) return widget.points;
    if (widget.googleMarkers != null && widget.googleMarkers!.isNotEmpty) {
      return widget.googleMarkers!
          .where((m) => m.position.latitude != 0.0 && m.position.longitude != 0.0)
          .map((m) => AdaptiveMapPoint(
                id: m.markerId.value,
                latitude: m.position.latitude,
                longitude: m.position.longitude,
                title: m.infoWindow.title ?? '',
                snippet: m.infoWindow.snippet ?? '',
                onTap: m.onTap,
              ))
          .toList();
    }
    return const [];
  }

  List<AdaptivePolyline> get _effectivePolylines {
    if (widget.polylines.isNotEmpty) return widget.polylines;
    if (widget.googlePolylines != null && widget.googlePolylines!.isNotEmpty) {
      return widget.googlePolylines!
          .map((p) => AdaptivePolyline(
                id: p.polylineId.value,
                points: p.points.map((pt) => ll.LatLng(pt.latitude, pt.longitude)).toList(),
                color: p.color,
                strokeWidth: p.width.toDouble(),
              ))
          .toList();
    }
    return const [];
  }

  String _getTileUrl() {
    if (_tileSource == 'osm') {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    if (_tileSource == 'google_sat' || widget.mapType == gmaps.MapType.hybrid || widget.mapType == gmaps.MapType.satellite) {
      return 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    }
    if (_tileSource == 'google_terrain' || widget.mapType == gmaps.MapType.terrain) {
      return 'https://mt{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
    }
    return 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
  }

  List<String> _getSubdomains() {
    if (_tileSource == 'osm') return const ['a', 'b', 'c'];
    return const ['0', '1', '2', '3'];
  }

  String _getTileLabel() {
    if (_tileSource == 'osm') return 'OpenStreetMap';
    if (_tileSource == 'google_sat' || widget.mapType == gmaps.MapType.hybrid || widget.mapType == gmaps.MapType.satellite) {
      return 'Satellite';
    }
    if (_tileSource == 'google_terrain' || widget.mapType == gmaps.MapType.terrain) {
      return 'Terrain';
    }
    return 'Google Road';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _useLibreMap) {
      return _buildLibreOpenStreetMap();
    } else {
      return _buildGoogleMap();
    }
  }

  // 100% Free OpenStreetMap / Libre Map (Universal Web & Mobile Engine)
  Widget _buildLibreOpenStreetMap() {
    final center = ll.LatLng(widget.initialLat, widget.initialLng);
    final points = _effectivePoints;
    final polylines = _effectivePolylines;

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
            // Active Tile Layer (Google Road / Satellite / Terrain or OpenStreetMap)
            fmap.TileLayer(
              urlTemplate: _getTileUrl(),
              subdomains: _getSubdomains(),
              userAgentPackageName: 'com.mat.familytrack',
              maxZoom: 20,
            ),

            // Polyline Layer for Routes / History
            if (polylines.isNotEmpty)
              fmap.PolylineLayer(
                polylines: polylines.map((poly) {
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
            if (points.isNotEmpty)
              fmap.MarkerLayer(
                markers: points.map(_buildLibreMarker).toList(),
              ),
          ],
        ),

        // Map Attribution & Layer / Engine Switcher
        Positioned(
          top: 12,
          right: 12,
          child: _buildMapSwitcherButton(),
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

  fmap.Marker _buildLibreMarker(AdaptiveMapPoint p) {
    // 1. Waypoint / History Track Fix Marker: Centered directly on polyline vertex
    if (p.isWaypoint) {
      final isStart = p.isTripStart;
      final isEnd = p.isTripEnd;
      final isSelected = p.isSelected;

      if (isSelected) {
        // Selected waypoint: 100% centered on vertex with pulsing gold halo & floating card
        return fmap.Marker(
          point: ll.LatLng(p.latitude, p.longitude),
          width: 24.0,
          height: 24.0,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p.onTap,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Floating Callout Tooltip anchored directly above the vertex
                Positioned(
                  bottom: 26.0,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 190),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.title,
                          style: const TextStyle(
                            color: Color(0xFFFCD34D),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (p.snippet.isNotEmpty)
                          Text(
                            p.snippet,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 8.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                // Pulsing gold halo ring
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                    border: Border.all(color: const Color(0xFFF59E0B), width: 2),
                  ),
                ),
                // Core dot centered directly on the coordinate
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF59E0B),
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (isStart) {
        // Start waypoint: Centered green badge
        return fmap.Marker(
          point: ll.LatLng(p.latitude, p.longitude),
          width: 22.0,
          height: 22.0,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p.onTap,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
              ),
            ),
          ),
        );
      } else if (isEnd) {
        // End waypoint: Centered red badge
        return fmap.Marker(
          point: ll.LatLng(p.latitude, p.longitude),
          width: 22.0,
          height: 22.0,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p.onTap,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.flag_rounded, color: Colors.white, size: 11),
              ),
            ),
          ),
        );
      } else {
        // Intermediate waypoint dot: Clean 10px circular node centered on coordinate
        return fmap.Marker(
          point: ll.LatLng(p.latitude, p.longitude),
          width: 16.0,
          height: 16.0,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p.onTap,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.pinColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 2.5, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    // 2. Member & Safe Place Pin: Sharp tip anchored with mathematical precision at Alignment.bottomCenter
    final isSelected = p.isSelected && !p.isPlace;
    final pinColor = isSelected ? const Color(0xFFF59E0B) : p.pinColor;
    final avatarSize = p.isPlace ? 34.0 : (isSelected ? 40.0 : 32.0);
    final pointerHeight = p.isPlace ? 8.0 : (isSelected ? 10.0 : 8.0);
    final totalPinHeight = avatarSize + pointerHeight;
    final markerBoxWidth = avatarSize + 8.0;

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
            shape: p.isPlace ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: p.isPlace ? BorderRadius.circular(10) : null,
            color: pinColor,
            border: Border.all(
              color: Colors.white,
              width: isSelected ? 3.0 : 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: p.isPlace
                    ? pinColor.withValues(alpha: 0.45)
                    : isSelected
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                    : Colors.black.withValues(alpha: 0.35),
                blurRadius: p.isPlace ? 7 : (isSelected ? 10 : 5),
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
                      : Center(
                          child: Text(
                            p.title.isNotEmpty
                                ? p.title.replaceAll(RegExp(r'[^a-zA-Z]'), '').isNotEmpty
                                    ? p.title.replaceAll(RegExp(r'[^a-zA-Z]'), '')[0].toUpperCase()
                                    : p.title[0].toUpperCase()
                                : 'M',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSelected ? 16 : 13,
                              fontWeight: FontWeight.bold,
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
      width: markerBoxWidth,
      height: totalPinHeight,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: p.onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // A. Floating Name & Status Pill above the pin
            Positioned(
              bottom: totalPinHeight + 3,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 180),
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
                      p.isPlace ? 'SAFE PLACE · ${p.title}' : p.title,
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
            ),

            // B. Pin Avatar Body
            Positioned(
              top: 0,
              child: avatarCore,
            ),

            // C. Sharp Tapered Pointer Tip (converging to exact coordinate at bottom center)
            Positioned(
              top: avatarSize - 1.5,
              child: CustomPaint(
                size: Size(12, pointerHeight),
                painter: _PinPointerPainter(color: pinColor),
              ),
            ),

            // D. Precise Ground Contact Target Dot
            Positioned(
              bottom: 0,
              child: Container(
                width: 2.5,
                height: 2.5,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSwitcherButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Change Map Layer or Engine',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) async {
          if (value == 'engine_toggle') {
            final newMode = !_useLibreMap;
            await PreferencesService.setUseOpenStreetMap(newMode);
            setState(() {
              _useLibreMap = newMode;
            });
          } else {
            setState(() {
              _tileSource = value;
            });
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(
              'MAP STYLE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'google_road',
            child: Row(
              children: [
                Icon(
                  Icons.map_rounded,
                  size: 18,
                  color: _tileSource == 'google_road' ? AppColors.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Google Road Tiles',
                  style: TextStyle(
                    fontWeight: _tileSource == 'google_road' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'google_sat',
            child: Row(
              children: [
                Icon(
                  Icons.satellite_alt_rounded,
                  size: 18,
                  color: _tileSource == 'google_sat' ? AppColors.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Google Satellite',
                  style: TextStyle(
                    fontWeight: _tileSource == 'google_sat' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'google_terrain',
            child: Row(
              children: [
                Icon(
                  Icons.terrain_rounded,
                  size: 18,
                  color: _tileSource == 'google_terrain' ? AppColors.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Google Terrain',
                  style: TextStyle(
                    fontWeight: _tileSource == 'google_terrain' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'osm',
            child: Row(
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 18,
                  color: _tileSource == 'osm' ? AppColors.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'OpenStreetMap (OSM)',
                  style: TextStyle(
                    fontWeight: _tileSource == 'osm' ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (!kIsWeb) const PopupMenuDivider(),
          if (!kIsWeb)
            PopupMenuItem(
              value: 'engine_toggle',
              child: Row(
                children: [
                  Icon(
                    _useLibreMap ? Icons.phone_android_rounded : Icons.language_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _useLibreMap ? 'Switch to Google SDK' : 'Switch to Web/Open Tiles',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _tileSource == 'osm'
                    ? Icons.public_rounded
                    : (_tileSource == 'google_sat' ? Icons.satellite_alt_rounded : Icons.map_rounded),
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _useLibreMap ? _getTileLabel() : 'Native Google SDK',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
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

    return Stack(
      children: [
        gmaps.GoogleMap(
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
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildMapSwitcherButton(),
        ),
      ],
    );
  }
}

/// Custom painter for sharp pinpoint triangle anchored to exact coordinate
class _PinPointerPainter extends CustomPainter {
  final Color color;

  const _PinPointerPainter({required this.color});

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

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _PinPointerPainter oldDelegate) =>
      oldDelegate.color != color;
}