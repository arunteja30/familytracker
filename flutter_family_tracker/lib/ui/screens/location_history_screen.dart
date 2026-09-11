import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../services/geocoding_service.dart';
import '../widgets/adaptive_map_view.dart';

class LocationHistoryScreen extends StatefulWidget {
  final FamilyMemberModel member;

  const LocationHistoryScreen({super.key, required this.member});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _scrollController = ScrollController();
  DateTime _selectedDate = DateTime.now();
  List<LocationDetailsModel> _historyPoints = [];
  int? _selectedIndex;
  bool _isLoading = false;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

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
    });
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final points = await _dbService.getLocationHistory(widget.member.mobile, dateStr);

    _polylines.clear();
    final polylineCoords = <LatLng>[];

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        polylineCoords.add(LatLng(p.latitude, p.longitude));
      }
    }

    if (polylineCoords.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('history_route'),
          points: polylineCoords,
          color: AppColors.primary,
          width: 5,
        ),
      );

      // Fit map to polyline bounds
      _fitMapToBounds(polylineCoords);
    }

    if (mounted) {
      setState(() {
        _historyPoints = points;
        _isLoading = false;
        _buildMarkers();
      });
    }

    // Asynchronously enrich missing street addresses
    _resolveAddresses(points);
  }

  void _buildMarkers() {
    _markers.clear();

    for (int i = 0; i < _historyPoints.length; i++) {
      final p = _historyPoints[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        final pos = LatLng(p.latitude, p.longitude);
        final isSelected = _selectedIndex == i;
        final isStart = i == 0;
        final isEnd = i == _historyPoints.length - 1;

        // Always include start, end, selected point, or sampled points
        if (isSelected || isStart || isEnd || _historyPoints.length <= 15 || i % 4 == 0) {
          final timeStr = p.timeStamp > 0
              ? DateFormat('hh:mm a').format(
                  DateTime.fromMillisecondsSinceEpoch(p.timeStamp),
                )
              : '';

          final markerId = MarkerId('point_$i');

          BitmapDescriptor icon;
          if (isSelected) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
          } else if (isStart) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          } else if (isEnd) {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          } else {
            icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
          }

          _markers.add(
            Marker(
              markerId: markerId,
              position: pos,
              icon: icon,
              zIndexInt: isSelected ? 100 : (isEnd ? 10 : (isStart ? 9 : 1)),
              infoWindow: InfoWindow(
                title: isSelected
                    ? '📍 Selected (#${i + 1}) • $timeStr'
                    : (isStart
                        ? '🟢 Start Location ($timeStr)'
                        : isEnd
                            ? '🔴 Latest Location ($timeStr)'
                            : 'Point #${i + 1} ($timeStr)'),
                snippet: p.address.isNotEmpty
                    ? p.address
                    : 'Lat: ${p.latitude.toStringAsFixed(5)}, Lng: ${p.longitude.toStringAsFixed(5)}',
              ),
              onTap: () {
                _onMarkerTapped(i);
              },
            ),
          );
        }
      }
    }
  }

  void _onCardTapped(int index) {
    if (index >= _historyPoints.length) return;
    final p = _historyPoints[index];
    if (p.latitude == 0.0 && p.longitude == 0.0) return;

    setState(() {
      _selectedIndex = index;
      _buildMarkers();
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(p.latitude, p.longitude),
          zoom: 17,
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 350), () {
      _mapController?.showMarkerInfoWindow(MarkerId('point_$index'));
    });
  }

  void _onMarkerTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _buildMarkers();
    });
    _scrollToCard(index);
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
        _historyPoints = List.from(points);
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

    // Add slight padding to bounds
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
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _selectDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Filter Banner with Quick Prev/Next Navigation
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

          // Map Preview
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : AdaptiveMapView(
                    initialLat: initialPos.latitude,
                    initialLng: initialPos.longitude,
                    initialZoom: 14,
                    points: _historyPoints.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final isStart = i == 0;
                      final isEnd = i == _historyPoints.length - 1;
                      return AdaptiveMapPoint(
                        id: 'point_$i',
                        latitude: p.latitude,
                        longitude: p.longitude,
                        title: isStart
                            ? 'Start (${p.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(p.timeStamp)) : ''})'
                            : isEnd
                                ? 'Latest (${p.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(p.timeStamp)) : ''})'
                                : 'Point #${i + 1}',
                        snippet: p.address,
                        pinColor: isStart
                            ? AppColors.success
                            : isEnd
                                ? AppColors.danger
                                : AppColors.primary,
                      );
                    }).toList(),
                    polylines: [
                      AdaptivePolyline(
                        id: 'history_route',
                        points: _historyPoints
                            .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
                            .map((p) => ll.LatLng(p.latitude, p.longitude))
                            .toList(),
                        color: AppColors.primary,
                        strokeWidth: 4,
                      ),
                    ],
                    googleMarkers: _markers,
                    googlePolylines: _polylines,
                    onGoogleMapCreated: (ctrl) {
                      _mapController = ctrl;
                      if (_polylines.isNotEmpty) {
                        final coords = _polylines.first.points;
                        _fitMapToBounds(coords);
                      }
                    },
                  ),
          ),

          // Timeline Section
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.bgApp,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recorded Points (${_historyPoints.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (_historyPoints.isNotEmpty)
                        Text(
                          '${_historyPoints.first.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_historyPoints.first.timeStamp)) : ''} - ${_historyPoints.last.timeStamp > 0 ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_historyPoints.last.timeStamp)) : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _historyPoints.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_off_rounded,
                                  size: 40,
                                  color: AppColors.textMuted.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'No location points recorded on this date.',
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
                            itemCount: _historyPoints.length,
                            itemBuilder: (context, index) {
                              final p = _historyPoints[index];
                              final timeStr = p.timeStamp > 0
                                  ? DateFormat('hh:mm:ss a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        p.timeStamp,
                                      ),
                                    )
                                  : 'Point ${index + 1}';

                              final isStart = index == 0;
                              final isEnd = index == _historyPoints.length - 1;
                              final isSelected = _selectedIndex == index;

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.08)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.cardBorder,
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.25),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
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
                                        ? const Color(0xFFF59E0B) // Amber highlight
                                        : (isStart
                                            ? AppColors.success
                                            : isEnd
                                                ? AppColors.danger
                                                : AppColors.primaryLight),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.location_on_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 1. Lat & Lng Coordinates
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.gps_fixed_rounded,
                                            size: 11,
                                            color: AppColors.accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Lat: ${p.latitude.toStringAsFixed(6)}, Lng: ${p.longitude.toStringAsFixed(6)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),

                                      // 2. Street Address below Lat and Lng
                                      Text(
                                        p.address.isNotEmpty
                                            ? p.address
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
                                      '🕒 $timeStr • ⚡ ${p.batteryPercentage}%',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'ON MAP',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () => _onCardTapped(index),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
