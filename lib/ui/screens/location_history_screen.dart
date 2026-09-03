import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/family_member_model.dart';
import '../../models/location_details_model.dart';
import '../../services/database_service.dart';
import '../../services/geocoding_service.dart';

class LocationHistoryScreen extends StatefulWidget {
  final FamilyMemberModel member;

  const LocationHistoryScreen({super.key, required this.member});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  DateTime _selectedDate = DateTime.now();
  List<LocationDetailsModel> _historyPoints = [];
  bool _isLoading = false;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final points = await _dbService.getLocationHistory(widget.member.mobile, dateStr);

    _markers.clear();
    _polylines.clear();

    final polylineCoords = <LatLng>[];

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.latitude != 0.0 && p.longitude != 0.0) {
        final pos = LatLng(p.latitude, p.longitude);
        polylineCoords.add(pos);

        final timeStr = p.timeStamp > 0
            ? DateFormat('hh:mm a').format(
                DateTime.fromMillisecondsSinceEpoch(p.timeStamp),
              )
            : '';

        // Markers for start, intermediate (sampled), and end
        if (i == 0 || i == points.length - 1 || points.length <= 10 || i % 5 == 0) {
          final isStart = i == 0;
          final isEnd = i == points.length - 1;

          _markers.add(
            Marker(
              markerId: MarkerId('point_$i'),
              position: pos,
              icon: isStart
                  ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
                  : isEnd
                      ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
                      : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(
                title: isStart
                    ? 'Start Location ($timeStr)'
                    : isEnd
                        ? 'Latest Location ($timeStr)'
                        : 'Point #${i + 1} ($timeStr)',
                snippet: p.address,
              ),
            ),
          );
        }
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

    setState(() {
      _historyPoints = points;
      _isLoading = false;
    });

    // Asynchronously enrich missing street addresses
    _resolveAddresses(points);
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
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialPos,
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (ctrl) {
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
                                  color: AppColors.textMuted.withOpacity(0.5),
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
                            itemCount: _historyPoints.length,
                            itemBuilder: (context, index) {
                              final p = _historyPoints[index];
                              final timeStr = p.timeStamp > 0
                                  ? DateFormat('hh:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        p.timeStamp,
                                      ),
                                    )
                                  : 'Point ${index + 1}';

                              final isStart = index == 0;
                              final isEnd = index == _historyPoints.length - 1;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isStart
                                        ? AppColors.success
                                        : isEnd
                                            ? AppColors.danger
                                            : AppColors.primaryLight,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    p.address.isNotEmpty
                                        ? p.address
                                        : 'Lat: ${p.latitude.toStringAsFixed(4)}, Lon: ${p.longitude.toStringAsFixed(4)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$timeStr • Battery: ${p.batteryPercentage}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  onTap: () {
                                    _mapController?.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                        LatLng(p.latitude, p.longitude),
                                        16,
                                      ),
                                    );
                                  },
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
