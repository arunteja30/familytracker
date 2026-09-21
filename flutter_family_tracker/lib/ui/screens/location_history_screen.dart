import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/routing_service.dart';
import '../widgets/adaptive_map_view.dart';

enum HistoryTimeFilter {
  all,
  morning, // 06:00 - 12:00
  afternoon, // 12:00 - 18:00
  evening, // 18:00 - 24:00
  night, // 00:00 - 06:00
}

/// Curated distinct vibrant color palette for consecutive trips (30+ min gap)
const List<Color> _kTripColors = [
  Color(0xFF0284C7), // Trip 1: Vivid Sky Blue
  Color(0xFFEA580C), // Trip 2: Deep Sunset Orange
  Color(0xFF7C3AED), // Trip 3: Electric Purple
  Color(0xFF059669), // Trip 4: Emerald Green
  Color(0xFFDB2777), // Trip 5: Crimson Pink
  Color(0xFF0D9488), // Trip 6: Ocean Teal
  Color(0xFF4F46E5), // Trip 7: Royal Indigo
  Color(0xFFD97706), // Trip 8: Rich Amber
];

/// Helper to parse timestamps in milliseconds regardless of format
int _normalizeTimestampMs(int ts, String dateStr) {
  if (ts > 0) {
    if (ts < 10000000000) {
      return ts * 1000;
    }
    return ts;
  }
  if (dateStr.isNotEmpty) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) return dt.millisecondsSinceEpoch;
    } catch (_) {}
  }
  return 0;
}

/// Represents a distinct trip separated by 30+ minutes of inactivity
class HistoryTripSegment {
  final int tripNumber; // 1-based (Trip #1, Trip #2)
  final List<LocationDetailsModel> points; // Chronological order
  final Color color;
  final DateTime startTime;
  final DateTime endTime;
  RouteResult? routeResult;
  List<LatLng> routedCoords = [];

  HistoryTripSegment({
    required this.tripNumber,
    required this.points,
    required this.color,
    required this.startTime,
    required this.endTime,
  });

  bool get isSinglePoint => points.length <= 1;

  Duration get duration => endTime.difference(startTime);

  double get totalDistanceMeters {
    if (isSinglePoint) return 0.0;
    if (routeResult != null && routeResult!.distanceMeters > 0) {
      return routeResult!.distanceMeters;
    }
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }
    return total;
  }

  String get formattedDistance {
    if (isSinglePoint) return 'Single Point';
    final km = totalDistanceMeters / 1000.0;
    if (km < 1.0) {
      return '${totalDistanceMeters.toStringAsFixed(0)} m';
    }
    return '${km.toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    if (isSinglePoint) return 'Point';
    final mins = duration.inMinutes;
    if (mins < 1) return '< 1 min';
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final remainingMins = mins % 60;
    return '${hrs}h ${remainingMins}m';
  }
}

/// Fast O(1) metadata descriptor for rendering points and timeline cards
class _PointMeta {
  final HistoryTripSegment trip;
  final int updateNumber;
  final int stepInTrip;
  final bool isTripStart;
  final bool isTripEnd;
  final bool isSinglePoint;
  final String timeFormatted;

  const _PointMeta({
    required this.trip,
    required this.updateNumber,
    required this.stepInTrip,
    required this.isTripStart,
    required this.isTripEnd,
    required this.isSinglePoint,
    required this.timeFormatted,
  });
}

class LocationHistoryScreen extends StatefulWidget {
  final FamilyMemberModel member;

  const LocationHistoryScreen({super.key, required this.member});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  final fmap.MapController _flutterMapController = fmap.MapController();

  DateTime _selectedDate = DateTime.now();
  List<LocationDetailsModel> _rawHistoryPoints = [];
  List<LocationDetailsModel> _displayedPoints = [];
  final Map<LocationDetailsModel, int> _displayedIndexMap = {};
  final Map<LocationDetailsModel, _PointMeta> _pointMetaMap = {};

  List<HistoryTripSegment> _trips = [];
  HistoryTimeFilter _selectedTimeFilter = HistoryTimeFilter.all;
  int? _selectedIndex;
  int? _selectedTripIndex; // null means all trips
  bool _isLoading = false;

  // Directional Routing State
  RouteProfile _selectedRouteProfile = RouteProfile.bicycle;
  bool _isRoutingLoading = false;
  int _routingRequestId = 0;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<AdaptivePolyline> _adaptivePolylines = [];
  final List<AdaptiveMapPoint> _adaptivePoints = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _selectedIndex = null;
      _selectedTripIndex = null;
    });

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final points = await _dbService.getLocationHistory(widget.member.mobile, dateStr);

    if (mounted) {
      setState(() {
        _rawHistoryPoints = points;
        _applyTimeFilterAndRebuild();
        _isLoading = false;
      });
    }

    _resolveAddresses(points);
  }

  void _applyTimeFilterAndRebuild() {
    List<LocationDetailsModel> filtered;

    if (_selectedTimeFilter == HistoryTimeFilter.all) {
      filtered = List.from(_rawHistoryPoints);
    } else {
      filtered = _rawHistoryPoints.where((p) {
        final ts = _normalizeTimestampMs(p.timeStamp, p.date);
        if (ts <= 0) return true;
        final hour = DateTime.fromMillisecondsSinceEpoch(ts).hour;
        switch (_selectedTimeFilter) {
          case HistoryTimeFilter.morning:
            return hour >= 6 && hour < 12;
          case HistoryTimeFilter.afternoon:
            return hour >= 12 && hour < 18;
          case HistoryTimeFilter.evening:
            return hour >= 18 && hour < 24;
          case HistoryTimeFilter.night:
            return hour >= 0 && hour < 6;
          case HistoryTimeFilter.all:
            return true;
        }
      }).toList();
    }

    // 1. Sort latest update on top (Newest to Oldest) for timeline
    filtered.sort((a, b) {
      final tA = _normalizeTimestampMs(a.timeStamp, a.date);
      final tB = _normalizeTimestampMs(b.timeStamp, b.date);
      return tB.compareTo(tA);
    });

    _displayedPoints = filtered;
    _displayedIndexMap.clear();
    for (int i = 0; i < filtered.length; i++) {
      _displayedIndexMap[filtered[i]] = i;
    }

    // 2. Segment chronological points into distinct trips based on >= 30 min gap
    final chronological = List<LocationDetailsModel>.from(filtered)
      ..sort((a, b) {
        final tA = _normalizeTimestampMs(a.timeStamp, a.date);
        final tB = _normalizeTimestampMs(b.timeStamp, b.date);
        return tA.compareTo(tB);
      });

    _trips = _segmentHistoryIntoTrips(chronological);

    // 3. Precompute Point Metadata Map in O(N) for O(1) list item lookup
    _pointMetaMap.clear();
    for (final trip in _trips) {
      final isSingle = trip.isSinglePoint;
      for (int i = 0; i < trip.points.length; i++) {
        final pt = trip.points[i];
        final dispIdx = _displayedIndexMap[pt] ?? 0;
        final ts = _normalizeTimestampMs(pt.timeStamp, pt.date);
        final timeStr = ts > 0
            ? DateFormat('hh:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(ts))
            : 'Update ${dispIdx + 1}';

        _pointMetaMap[pt] = _PointMeta(
          trip: trip,
          updateNumber: filtered.length - dispIdx,
          stepInTrip: i + 1,
          isTripStart: !isSingle && i == 0,
          isTripEnd: !isSingle && i == trip.points.length - 1,
          isSinglePoint: isSingle,
          timeFormatted: timeStr,
        );
      }
    }

    // Initial direct polylines and markers build
    _rebuildMapElements(isSnapped: false);

    final allCoords = chronological
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    if (allCoords.isNotEmpty) {
      _fitMapToBounds(allCoords);
    }

    // 4. Asynchronously fetch OpenStreetMap / Libre bike road directional route for trips
    _fetchDirectionalRoutesForTrips();
  }

  List<HistoryTripSegment> _segmentHistoryIntoTrips(List<LocationDetailsModel> chronologicalPoints) {
    final validPoints = chronologicalPoints
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (validPoints.isEmpty) return [];

    final List<HistoryTripSegment> trips = [];
    List<LocationDetailsModel> currentTripPoints = [validPoints.first];

    for (int i = 1; i < validPoints.length; i++) {
      final prev = validPoints[i - 1];
      final curr = validPoints[i];

      final prevTs = _normalizeTimestampMs(prev.timeStamp, prev.date);
      final currTs = _normalizeTimestampMs(curr.timeStamp, curr.date);

      final timeGapMs = currTs - prevTs;
      final bool isNewTripGap = prevTs > 0 && currTs > 0 && timeGapMs >= (30 * 60 * 1000);

      if (isNewTripGap) {
        final color = _kTripColors[trips.length % _kTripColors.length];
        final startTs = _normalizeTimestampMs(currentTripPoints.first.timeStamp, currentTripPoints.first.date);
        final endTs = _normalizeTimestampMs(currentTripPoints.last.timeStamp, currentTripPoints.last.date);

        trips.add(
          HistoryTripSegment(
            tripNumber: trips.length + 1,
            points: List.from(currentTripPoints),
            color: color,
            startTime: startTs > 0 ? DateTime.fromMillisecondsSinceEpoch(startTs) : DateTime.now(),
            endTime: endTs > 0 ? DateTime.fromMillisecondsSinceEpoch(endTs) : DateTime.now(),
          ),
        );
        currentTripPoints = [curr];
      } else {
        currentTripPoints.add(curr);
      }
    }

    if (currentTripPoints.isNotEmpty) {
      final color = _kTripColors[trips.length % _kTripColors.length];
      final startTs = _normalizeTimestampMs(currentTripPoints.first.timeStamp, currentTripPoints.first.date);
      final endTs = _normalizeTimestampMs(currentTripPoints.last.timeStamp, currentTripPoints.last.date);

      trips.add(
        HistoryTripSegment(
          tripNumber: trips.length + 1,
          points: List.from(currentTripPoints),
          color: color,
          startTime: startTs > 0 ? DateTime.fromMillisecondsSinceEpoch(startTs) : DateTime.now(),
          endTime: endTs > 0 ? DateTime.fromMillisecondsSinceEpoch(endTs) : DateTime.now(),
        ),
      );
    }

    return trips;
  }

  Future<void> _fetchDirectionalRoutesForTrips() async {
    final reqId = ++_routingRequestId;

    if (_trips.isEmpty) {
      if (mounted) setState(() => _isRoutingLoading = false);
      return;
    }

    final routableTrips = _trips.where((t) => t.points.length >= 2).toList();
    if (routableTrips.isEmpty) {
      if (mounted) setState(() => _isRoutingLoading = false);
      return;
    }

    setState(() {
      _isRoutingLoading = true;
    });

    try {
      // Parallelize route fetching across all trips for maximum network efficiency
      await Future.wait(
        routableTrips.map((trip) async {
          final coords = trip.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
          final result = await RoutingService.getRoute(
            waypoints: coords,
            profile: _selectedRouteProfile,
          );
          trip.routeResult = result;
          trip.routedCoords = result.points.isNotEmpty ? result.points : coords;
        }),
      );

      if (mounted && reqId == _routingRequestId) {
        setState(() {
          _rebuildMapElements(isSnapped: true);
          _isRoutingLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[LocationHistoryScreen] Routing fetch error: $e');
      if (mounted && reqId == _routingRequestId) {
        setState(() => _isRoutingLoading = false);
      }
    }
  }

  void _rebuildMapElements({bool isSnapped = false}) {
    _polylines.clear();
    _adaptivePolylines.clear();
    _markers.clear();
    _adaptivePoints.clear();

    final formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDate);

    // 1. Polylines
    for (int t = 0; t < _trips.length; t++) {
      final trip = _trips[t];
      if (trip.points.length < 2) continue;
      if (_selectedTripIndex != null && _selectedTripIndex != trip.tripNumber) {
        continue;
      }

      // Directional road route is used when available; smooth spline as fallback
      final List<LatLng> coords = trip.routedCoords.isNotEmpty
          ? trip.routedCoords
          : _generateSmoothCurve(trip.points.map((p) => LatLng(p.latitude, p.longitude)).toList());

      if (coords.length < 2) continue;

      _polylines.add(
        Polyline(
          polylineId: PolylineId('trip_${trip.tripNumber}'),
          points: List.from(coords),
          color: trip.color,
          width: isSnapped ? 6 : 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );

      _adaptivePolylines.add(
        AdaptivePolyline(
          id: 'trip_${trip.tripNumber}',
          points: coords.map((p) => ll.LatLng(p.latitude, p.longitude)).toList(),
          color: trip.color,
          strokeWidth: isSnapped ? 5.5 : 4.0,
        ),
      );
    }

    // 2. Markers & Web Map Points
    for (final trip in _trips) {
      if (_selectedTripIndex != null && _selectedTripIndex != trip.tripNumber) {
        continue;
      }

      final points = trip.points;
      if (points.isEmpty) continue;
      final isSinglePointTrip = points.length == 1;

      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final pos = LatLng(p.latitude, p.longitude);

        final displayedIdx = _displayedIndexMap[p] ?? -1;
        final isSelected = _selectedIndex == displayedIdx;
        final isTripStart = !isSinglePointTrip && i == 0;
        final isTripEnd = !isSinglePointTrip && i == points.length - 1;

        if (isSelected ||
            isSinglePointTrip ||
            isTripStart ||
            isTripEnd ||
            points.length <= 8 ||
            i % 2 == 0) {
          final ts = _normalizeTimestampMs(p.timeStamp, p.date);
          final timeStr = ts > 0
              ? DateFormat('hh:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(ts))
              : '';
          final shortTimeStr = ts > 0
              ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts))
              : '';

          final updateNum = displayedIdx != -1 ? (_displayedPoints.length - displayedIdx) : (i + 1);
          final markerId = MarkerId('trip_${trip.tripNumber}_point_$i');

          BitmapDescriptor icon;
          String label;

          if (isSelected) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
            label = isSinglePointTrip
                ? '📍 Selected #$updateNum • Single Point (Trip #${trip.tripNumber})'
                : '📍 Selected #$updateNum • Trip #${trip.tripNumber}';
          } else if (isSinglePointTrip) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
            label = '📍 #$updateNum • Single Point (Trip #${trip.tripNumber})';
          } else if (isTripStart) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
            label = '🟢 #$updateNum • Trip #${trip.tripNumber} Start';
          } else if (isTripEnd) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
            label = '🏁 #$updateNum • Trip #${trip.tripNumber} End';
          } else {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
            label = '📍 #$updateNum • Trip #${trip.tripNumber} (Step ${i + 1})';
          }

          final addr = p.address.isNotEmpty
              ? p.address
              : 'Lat: ${p.latitude.toStringAsFixed(5)}, Lng: ${p.longitude.toStringAsFixed(5)}';

          _markers.add(
            Marker(
              markerId: markerId,
              position: pos,
              icon: icon,
              zIndexInt: isSelected
                  ? 100
                  : (isSinglePointTrip
                      ? 20
                      : (isTripEnd ? 30 : (isTripStart ? 25 : 10))),
              infoWindow: InfoWindow(
                title: label,
                snippet: '📅 $formattedDate • 🕒 $timeStr\n📍 $addr\n⚡ Battery: ${p.batteryPercentage}%',
              ),
              onTap: () {
                if (displayedIdx != -1) {
                  _onMarkerTapped(displayedIdx);
                }
              },
            ),
          );

          _adaptivePoints.add(
            AdaptiveMapPoint(
              id: 'trip_${trip.tripNumber}_$i',
              latitude: p.latitude,
              longitude: p.longitude,
              title: isSinglePointTrip
                  ? '📍 #$updateNum • Point ($shortTimeStr)'
                  : (isTripStart
                      ? '🟢 #$updateNum Start ($shortTimeStr)'
                      : (isTripEnd ? '🏁 #$updateNum End ($shortTimeStr)' : '#$updateNum ($shortTimeStr)')),
              snippet: 'Trip #${trip.tripNumber} • $addr',
              pinColor: isSinglePointTrip
                  ? trip.color
                  : (isTripStart ? AppColors.success : (isTripEnd ? AppColors.danger : trip.color)),
              isSelected: isSelected,
              onTap: () {
                if (displayedIdx != -1) {
                  _onMarkerTapped(displayedIdx);
                }
              },
            ),
          );
        }
      }
    }
  }

  /// Generate smooth Catmull-Rom spline curves between discrete GPS update points
  List<LatLng> _generateSmoothCurve(List<LatLng> points, {int stepsPerSegment = 10}) {
    if (points.length < 3) {
      return List.from(points);
    }

    final List<LatLng> smoothPoints = [];
    final int n = points.length;

    for (int i = 0; i < n - 1; i++) {
      final p0 = i == 0
          ? LatLng(2 * points[0].latitude - points[1].latitude,
                   2 * points[0].longitude - points[1].longitude)
          : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < n
          ? points[i + 2]
          : LatLng(2 * points[n - 1].latitude - points[n - 2].latitude,
                   2 * points[n - 1].longitude - points[n - 2].longitude);

      for (int step = 0; step < stepsPerSegment; step++) {
        final double t = step / stepsPerSegment;
        final double t2 = t * t;
        final double t3 = t2 * t;

        final double lat = 0.5 * (
          (2 * p1.latitude) +
          (-p0.latitude + p2.latitude) * t +
          (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2 +
          (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3
        );

        final double lng = 0.5 * (
          (2 * p1.longitude) +
          (-p0.longitude + p2.longitude) * t +
          (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2 +
          (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3
        );

        smoothPoints.add(LatLng(lat, lng));
      }
    }

    // Append exact final endpoint
    smoothPoints.add(points.last);
    return smoothPoints;
  }

  /// Bidirectional Tap from Timeline Card -> Map Focus + Marker Highlight + Trip Selection
  void _onCardTapped(int index) {
    if (index >= _displayedPoints.length) return;
    final p = _displayedPoints[index];
    if (p.latitude == 0.0 && p.longitude == 0.0) return;

    final meta = _pointMetaMap[p];

    setState(() {
      _selectedIndex = index;
      if (meta != null) {
        _selectedTripIndex = meta.trip.tripNumber;
      }
      _rebuildMapElements(isSnapped: true);
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(p.latitude, p.longitude),
          zoom: 17,
        ),
      ),
    );

    try {
      _flutterMapController.move(
        ll.LatLng(p.latitude, p.longitude),
        17,
      );
    } catch (_) {}
  }

  /// Bidirectional Tap from Map Marker -> Timeline Card Auto-Scroll + Highlight + Trip Selection
  void _onMarkerTapped(int index) {
    if (index >= _displayedPoints.length) return;
    final p = _displayedPoints[index];

    final meta = _pointMetaMap[p];

    setState(() {
      _selectedIndex = index;
      if (meta != null) {
        _selectedTripIndex = meta.trip.tripNumber;
      }
      _rebuildMapElements(isSnapped: true);
    });

    _scrollToCard(index);

    if (p.latitude != 0.0 && p.longitude != 0.0) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(p.latitude, p.longitude),
            zoom: 17,
          ),
        ),
      );

      try {
        _flutterMapController.move(
          ll.LatLng(p.latitude, p.longitude),
          17,
        );
      } catch (_) {}
    }
  }

  void _scrollToCard(int index) {
    if (_scrollController.hasClients) {
      const itemHeight = 90.0;
      final targetOffset = (index * itemHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _resolveAddresses(List<LocationDetailsModel> points) async {
    bool updated = false;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.address.isEmpty || p.address.startsWith('Lat:')) {
        final resolved = await GeocodingService.getAddressFromCoordinates(
          p.latitude,
          p.longitude,
        );
        if (resolved.isNotEmpty && !resolved.startsWith('Lat:')) {
          p.address = resolved;
          updated = true;
        }
      }
    }
    if (updated && mounted) {
      setState(() {
        _applyTimeFilterAndRebuild();
      });
    }
  }

  void _fitMapToBounds(List<LatLng> coords) {
    if (_mapController == null || coords.isEmpty) return;

    double minLat = coords.first.latitude;
    double maxLat = coords.first.latitude;
    double minLng = coords.first.longitude;
    double maxLng = coords.first.longitude;

    for (var pos in coords) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchHistory();
    }
  }

  void _changeDateByDays(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    if (newDate.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = newDate);
    _fetchHistory();
  }

  Future<void> _showClearHistoryDialog() async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Clear History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Choose which location history to delete for ${widget.member.name}:',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performClearHistory(dateStr: formattedDate);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete $formattedDate'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performClearHistory(dateStr: null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete All History'),
          ),
        ],
      ),
    );
  }

  Future<void> _performClearHistory({String? dateStr}) async {
    setState(() => _isLoading = true);
    try {
      await _dbService.clearLocationHistory(widget.member.mobile, date: dateStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dateStr != null
                  ? 'History for $dateStr cleared.'
                  : 'All location history cleared for ${widget.member.name}.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _fetchHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear history: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalDistanceAllTripsKm {
    double totalMeters = 0.0;
    for (final t in _trips) {
      totalMeters += t.totalDistanceMeters;
    }
    return totalMeters / 1000.0;
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, MMM dd, yyyy').format(_selectedDate);
    final initialPos = _markers.isNotEmpty
        ? _markers.first.position
        : const LatLng(17.3850, 78.4867);

    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.member.name} History'),
        actions: [
          // Route Profile Selector Popup Menu
          PopupMenuButton<RouteProfile>(
            icon: Tooltip(
              message: 'Route Mode: ${_selectedRouteProfile.label}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_selectedRouteProfile.icon, style: const TextStyle(fontSize: 16)),
                  const Icon(Icons.arrow_drop_down_rounded, size: 20),
                ],
              ),
            ),
            tooltip: 'Select Directional Route Profile',
            initialValue: _selectedRouteProfile,
            onSelected: (profile) {
              setState(() {
                _selectedRouteProfile = profile;
              });
              _fetchDirectionalRoutesForTrips();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: RouteProfile.bicycle,
                child: Row(
                  children: [
                    Text('🚲', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bike Roads (OSM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('OpenStreetMap Bike Paths', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: RouteProfile.driving,
                child: Row(
                  children: [
                    Text('🚗', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Driving Route', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('OSRM Road Directions', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: RouteProfile.foot,
                child: Row(
                  children: [
                    Text('🚶', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Walking Paths', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Pedestrian / Footways', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: RouteProfile.direct,
                child: Row(
                  children: [
                    Text('📏', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Direct GPS Path', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Straight Point-to-Point', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Clear / Delete History Button
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear History',
            onPressed: _showClearHistoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Select Date',
            onPressed: _selectDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Filter Banner with Quick Prev/Next Navigation
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
                  onPressed: () => _changeDateByDays(-1),
                  tooltip: 'Previous Day',
                ),
                InkWell(
                  onTap: _selectDate,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: isToday ? AppColors.textMuted : AppColors.primary,
                  ),
                  onPressed: isToday ? null : () => _changeDateByDays(1),
                  tooltip: 'Next Day',
                ),
              ],
            ),
          ),

          // Body: Loading, Empty State, or Map + Timeline
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rawHistoryPoints.isEmpty)
            Expanded(
              child: _buildNoHistoryEmptyState(formattedDate),
            )
          else ...[
            // 1. Map Preview with Multi-Trip Colored Road Routes
            Expanded(
              flex: 3,
              child: _displayedPoints.isEmpty
                  ? Container(
                      color: AppColors.bgSurface,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 40,
                              color: AppColors.textMuted.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No points in selected time filter',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedTimeFilter = HistoryTimeFilter.all;
                                  _applyTimeFilterAndRebuild();
                                });
                              },
                              child: const Text('Show All Updates'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        AdaptiveMapView(
                          initialLat: initialPos.latitude,
                          initialLng: initialPos.longitude,
                          initialZoom: 14,
                          points: _adaptivePoints,
                          polylines: List<AdaptivePolyline>.from(_adaptivePolylines),
                          googleMarkers: Set<Marker>.from(_markers),
                          googlePolylines: Set<Polyline>.from(_polylines),
                          flutterMapController: _flutterMapController,
                          onGoogleMapCreated: (ctrl) {
                            _mapController = ctrl;
                            if (_polylines.isNotEmpty) {
                              final coords = _polylines.expand((p) => p.points).toList();
                              if (coords.isNotEmpty) {
                                _fitMapToBounds(coords);
                              }
                            }
                          },
                        ),

                        // Floating Trip Statistics & Mode Badge
                        Positioned(
                          top: 12,
                          left: 12,
                          child: RepaintBoundary(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(12),
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
                                  Text(
                                    _selectedRouteProfile.icon,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_isRoutingLoading) ...[
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Routing trips on roads...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ] else ...[
                                    Text(
                                      '${_trips.length} ${_trips.length == 1 ? "Trip" : "Trips"} • ${_totalDistanceAllTripsKm.toStringAsFixed(2)} km',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0F2FE),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '≥30m Split',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0369A1),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            // 2. Timeline Section with Trip Chips & Time Filter Chips
            Expanded(
              flex: 3,
              child: Container(
                color: AppColors.bgApp,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Total Points & Latest Timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Updates (${_displayedPoints.length}) • ${_trips.length} Trips',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (_displayedPoints.isNotEmpty)
                          Text(
                            'Latest: ${_normalizeTimestampMs(_displayedPoints.first.timeStamp, _displayedPoints.first.date) > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_normalizeTimestampMs(_displayedPoints.first.timeStamp, _displayedPoints.first.date))) : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Trip Filter Selector (All Trips or Specific Trip)
                    if (_trips.length > 1) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedTripIndex = null;
                                  _rebuildMapElements(isSnapped: true);
                                });
                                final allCoords = _rawHistoryPoints
                                    .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
                                    .map((p) => LatLng(p.latitude, p.longitude))
                                    .toList();
                                if (allCoords.isNotEmpty) {
                                  _fitMapToBounds(allCoords);
                                  try {
                                    _flutterMapController.move(
                                      ll.LatLng(allCoords.first.latitude, allCoords.first.longitude),
                                      14,
                                    );
                                  } catch (_) {}
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: _selectedTripIndex == null
                                      ? AppColors.primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedTripIndex == null
                                        ? AppColors.primary
                                        : AppColors.cardBorder,
                                  ),
                                ),
                                child: Text(
                                  'All Trips (${_trips.length})',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTripIndex == null
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            ..._trips.map((trip) {
                              final isTripSelected = _selectedTripIndex == trip.tripNumber;
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedTripIndex = isTripSelected ? null : trip.tripNumber;
                                    _rebuildMapElements(isSnapped: true);
                                  });
                                  final coords = trip.points
                                      .map((p) => LatLng(p.latitude, p.longitude))
                                      .toList();
                                  if (coords.isNotEmpty) {
                                    _fitMapToBounds(coords);
                                    try {
                                      _flutterMapController.move(
                                        ll.LatLng(coords.first.latitude, coords.first.longitude),
                                        15,
                                      );
                                    } catch (_) {}
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isTripSelected
                                        ? trip.color
                                        : trip.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: trip.color),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isTripSelected ? Colors.white : trip.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Trip ${trip.tripNumber} (${trip.formattedDistance})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isTripSelected ? Colors.white : trip.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // Time Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('All (${_rawHistoryPoints.length})', HistoryTimeFilter.all),
                          const SizedBox(width: 6),
                          _buildFilterChip('🌅 Morning (6AM-12PM)', HistoryTimeFilter.morning),
                          const SizedBox(width: 6),
                          _buildFilterChip('☀️ Afternoon (12PM-6PM)', HistoryTimeFilter.afternoon),
                          const SizedBox(width: 6),
                          _buildFilterChip('🌆 Evening (6PM-12AM)', HistoryTimeFilter.evening),
                          const SizedBox(width: 6),
                          _buildFilterChip('🌙 Night (12AM-6AM)', HistoryTimeFilter.night),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Timeline Cards List (Newest on Top)
                    Expanded(
                      child: _displayedPoints.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.location_off_rounded,
                                    size: 36,
                                    color: AppColors.textMuted.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'No recorded points in this time range.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _displayedPoints.length,
                              itemBuilder: (context, index) {
                                final p = _displayedPoints[index];
                                final meta = _pointMetaMap[p];
                                final updateNum = meta?.updateNumber ?? (_displayedPoints.length - index);
                                final isLatest = index == 0;
                                final isSelected = _selectedIndex == index;

                                // Check if there's a 30+ min gap to the next older item below
                                String? gapNotice;
                                if (index < _displayedPoints.length - 1) {
                                  final nextOlderPoint = _displayedPoints[index + 1];
                                  final ts = _normalizeTimestampMs(p.timeStamp, p.date);
                                  final nextOlderTs = _normalizeTimestampMs(nextOlderPoint.timeStamp, nextOlderPoint.date);
                                  if (ts > 0 && nextOlderTs > 0) {
                                    final gapMs = ts - nextOlderTs;
                                    if (gapMs >= 30 * 60 * 1000) {
                                      final gapMins = gapMs ~/ (60 * 1000);
                                      final gapHours = gapMins ~/ 60;
                                      final remMins = gapMins % 60;
                                      gapNotice = gapHours > 0
                                          ? '⏸️ ${gapHours}h ${remMins}m Inactive Gap (New Trip Start Above)'
                                          : '⏸️ ${gapMins}m Inactive Gap (New Trip Start Above)';
                                    }
                                  }
                                }

                                return _TimelineHistoryCard(
                                  point: p,
                                  updateNum: updateNum,
                                  trip: meta?.trip,
                                  isSelected: isSelected,
                                  isLatest: isLatest,
                                  isTripStart: meta?.isTripStart ?? false,
                                  isTripEnd: meta?.isTripEnd ?? false,
                                  isSinglePoint: meta?.isSinglePoint ?? false,
                                  timeStr: meta?.timeFormatted ?? '',
                                  gapNotice: gapNotice,
                                  onTap: () => _onCardTapped(index),
                                  onTripBadgeTap: meta != null
                                      ? () {
                                          setState(() {
                                            _selectedTripIndex = _selectedTripIndex == meta.trip.tripNumber
                                                ? null
                                                : meta.trip.tripNumber;
                                            _rebuildMapElements(isSnapped: true);
                                          });
                                        }
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, HistoryTimeFilter filter) {
    final isSelected = _selectedTimeFilter == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTimeFilter = filter;
          _selectedIndex = null;
          _selectedTripIndex = null;
          _applyTimeFilterAndRebuild();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNoHistoryEmptyState(String formattedDate) {
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.route_outlined,
                size: 46,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Location History Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No GPS location updates were recorded for ${widget.member.name} on $formattedDate.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Pick Date'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (!isToday)
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _selectedDate = DateTime.now());
                      _fetchHistory();
                    },
                    icon: const Icon(Icons.today_rounded, size: 18),
                    label: const Text("Today's History"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                IconButton.filledTonal(
                  onPressed: _fetchHistory,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Decoupled, optimized timeline history card for 60/120fps scrolling
class _TimelineHistoryCard extends StatelessWidget {
  final LocationDetailsModel point;
  final int updateNum;
  final HistoryTripSegment? trip;
  final bool isSelected;
  final bool isLatest;
  final bool isTripStart;
  final bool isTripEnd;
  final bool isSinglePoint;
  final String timeStr;
  final String? gapNotice;
  final VoidCallback onTap;
  final VoidCallback? onTripBadgeTap;

  const _TimelineHistoryCard({
    required this.point,
    required this.updateNum,
    required this.trip,
    required this.isSelected,
    required this.isLatest,
    required this.isTripStart,
    required this.isTripEnd,
    required this.isSinglePoint,
    required this.timeStr,
    required this.gapNotice,
    required this.onTap,
    this.onTripBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    final tripColor = trip?.color ?? AppColors.primary;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF59E0B)
                  : (isLatest
                      ? AppColors.danger.withValues(alpha: 0.5)
                      : AppColors.cardBorder),
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: isSelected
                  ? const Color(0xFFF59E0B)
                  : (isSinglePoint
                      ? tripColor
                      : (isTripEnd
                          ? AppColors.danger
                          : (isTripStart
                              ? AppColors.success
                              : tripColor))),
              child: Text(
                '#$updateNum',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 1. Update Number Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: isLatest
                            ? AppColors.dangerBg
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isLatest ? AppColors.danger : const Color(0xFFCBD5E1),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isLatest ? '#$updateNum (LATEST)' : '#$updateNum',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isLatest ? AppColors.danger : const Color(0xFF334155),
                        ),
                      ),
                    ),

                    // 2. Trip Badge with distinct trip color
                    if (trip != null) ...[
                      GestureDetector(
                        onTap: onTripBadgeTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: tripColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tripColor, width: 0.8),
                          ),
                          child: Text(
                            'TRIP #${trip!.tripNumber}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: tripColor,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (isSinglePoint) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: tripColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'POINT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: tripColor,
                          ),
                        ),
                      ),
                    ] else if (isTripStart) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'START',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ] else if (isTripEnd) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'END',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],

                    const Icon(
                      Icons.gps_fixed_rounded,
                      size: 11,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Lat: ${point.latitude.toStringAsFixed(5)}, Lng: ${point.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFFD97706)
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  point.address.isNotEmpty
                      ? point.address
                      : 'Fetching street address...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '🕒 $timeStr • ⚡ ${point.batteryPercentage}%',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: isSelected
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SELECTED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
            onTap: onTap,
          ),
        ),

        // Inactive 30+ min gap banner separator between distinct trips
        if (gapNotice != null) ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gapNotice!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
